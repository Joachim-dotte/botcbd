package chat.simplex.common.sovereign

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.AtomicFile
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import chat.simplex.common.platform.androidAppContext
import java.io.BufferedInputStream
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

private object AndroidSovereignRegistry : SovereignRegistry {
  private const val KEY_ALIAS = "sovereign.registry.hmac.v1"
  private const val MAGIC = 0x534F5652
  private const val VERSION = 1
  private const val MAX_ENTRIES = 1024
  private const val MAX_RECORD_BYTES = 512
  private const val MAX_FILE_BYTES = 1024 * 1024L
  private val domain = "SOVEREIGN-REGISTRY-EVENT-V1\u0000".toByteArray(StandardCharsets.US_ASCII)
  private val scopeDomain = "SOVEREIGN-REGISTRY-SCOPE-V1\u0000".toByteArray(StandardCharsets.US_ASCII)
  private val states = mutableMapOf<String, androidx.compose.runtime.MutableState<SovereignRegistrySnapshot>>()
  private val lock = Any()

  override fun snapshot(scope: Long?): State<SovereignRegistrySnapshot> = synchronized(lock) {
    val token = scopeToken(scope) ?: return@synchronized mutableStateOf(
      SovereignRegistrySnapshot(SovereignRegistryIntegrity.KEY_UNAVAILABLE)
    )
    states.getOrPut(token) { mutableStateOf(readVerified(token)) }
  }

  override fun refresh(scope: Long?) {
    synchronized(lock) {
      val token = scopeToken(scope) ?: return
      states.getOrPut(token) { mutableStateOf(SovereignRegistrySnapshot.unsupported()) }.value = readVerified(token)
    }
  }

  override fun append(
    scope: Long?,
    code: SovereignDiagnosticEventCode,
    rawFields: Map<String, String>,
  ): Boolean = synchronized(lock) {
    val token = scopeToken(scope) ?: return@synchronized false
    val current = readVerified(token)
    if (current.integrity == SovereignRegistryIntegrity.TAMPERED ||
      current.integrity == SovereignRegistryIntegrity.KEY_UNAVAILABLE
    ) return@synchronized false
    if (current.entries.size >= MAX_ENTRIES) return@synchronized false

    val sequence = (current.entries.lastOrNull()?.sequence ?: 0L) + 1L
    val fields = SovereignDiagnosticFieldPolicy.sanitize(rawFields).toSortedMap()
    val payload = encodePayload(
      SovereignRegistryEntry(
        sequence = sequence,
        timeBucketHours = System.currentTimeMillis() / 3_600_000L,
        code = code,
        fields = fields,
      )
    )
    if (payload.size > MAX_RECORD_BYTES) return@synchronized false
    val previous = current.headFingerprint?.let(::hexToBytes) ?: ByteArray(32)
    val mac = eventMac(token, payload, previous) ?: return@synchronized false
    val head = sha256(previous + payload + mac)
    val file = scopeFile(token)
    file.parentFile?.mkdirs()
    val record = ByteArrayOutputStream().also { bytes ->
      DataOutputStream(bytes).use { data ->
        data.writeInt(payload.size)
        data.write(payload)
        data.write(previous)
        data.write(mac)
        data.write(head)
      }
    }.toByteArray()
    val prefix = if (file.exists()) {
      if (file.length() <= 0L || file.length() > MAX_FILE_BYTES) return@synchronized false
      try { file.readBytes() } catch (_: Exception) { return@synchronized false }
    } else {
      ByteArrayOutputStream().also { bytes ->
        DataOutputStream(bytes).use { data ->
          data.writeInt(MAGIC)
          data.writeInt(VERSION)
        }
      }.toByteArray()
    }
    if (prefix.size.toLong() + record.size.toLong() > MAX_FILE_BYTES) return@synchronized false
    val atomicFile = AtomicFile(file)
    var output: FileOutputStream? = null
    try {
      val activeOutput = atomicFile.startWrite()
      output = activeOutput
      activeOutput.write(prefix)
      activeOutput.write(record)
      activeOutput.fd.sync()
      atomicFile.finishWrite(activeOutput)
      output = null
    } catch (_: Exception) {
      output?.let(atomicFile::failWrite)
      return@synchronized false
    }
    states.getOrPut(token) { mutableStateOf(current) }.value = readVerified(token)
    true
  }

  private fun readVerified(token: String): SovereignRegistrySnapshot {
    val file = scopeFile(token)
    if (!file.exists()) return SovereignRegistrySnapshot(SovereignRegistryIntegrity.EMPTY)
    if (file.length() <= 0 || file.length() > MAX_FILE_BYTES) {
      return SovereignRegistrySnapshot(SovereignRegistryIntegrity.TAMPERED)
    }
    val entries = mutableListOf<SovereignRegistryEntry>()
    var expectedPrevious = ByteArray(32)
    return try {
      DataInputStream(BufferedInputStream(FileInputStream(file))).use { input ->
        if (input.readInt() != MAGIC || input.readInt() != VERSION) {
          return SovereignRegistrySnapshot(SovereignRegistryIntegrity.TAMPERED)
        }
        while (true) {
          val length = try { input.readInt() } catch (_: EOFException) { break }
          if (length !in 1..MAX_RECORD_BYTES || entries.size >= MAX_ENTRIES) {
            return SovereignRegistrySnapshot(SovereignRegistryIntegrity.TAMPERED)
          }
          val payload = ByteArray(length).also(input::readFully)
          val previous = ByteArray(32).also(input::readFully)
          val storedMac = ByteArray(32).also(input::readFully)
          val storedHead = ByteArray(32).also(input::readFully)
          if (!MessageDigest.isEqual(previous, expectedPrevious)) {
            return SovereignRegistrySnapshot(SovereignRegistryIntegrity.TAMPERED)
          }
          val expectedMac = eventMac(token, payload, previous)
            ?: return SovereignRegistrySnapshot(SovereignRegistryIntegrity.KEY_UNAVAILABLE)
          val expectedHead = sha256(previous + payload + expectedMac)
          if (!MessageDigest.isEqual(storedMac, expectedMac) || !MessageDigest.isEqual(storedHead, expectedHead)) {
            return SovereignRegistrySnapshot(SovereignRegistryIntegrity.TAMPERED)
          }
          val entry = decodePayload(payload)
            ?: return SovereignRegistrySnapshot(SovereignRegistryIntegrity.TAMPERED)
          if (entry.sequence != entries.size.toLong() + 1L) {
            return SovereignRegistrySnapshot(SovereignRegistryIntegrity.TAMPERED)
          }
          entries += entry
          expectedPrevious = storedHead
        }
      }
      SovereignRegistrySnapshot(
        integrity = if (entries.isEmpty()) SovereignRegistryIntegrity.EMPTY else SovereignRegistryIntegrity.VALID,
        entries = entries,
        headFingerprint = expectedPrevious.toHex(),
      )
    } catch (_: Exception) {
      SovereignRegistrySnapshot(SovereignRegistryIntegrity.TAMPERED)
    }
  }

  private fun encodePayload(entry: SovereignRegistryEntry): ByteArray {
    val bytes = ByteArrayOutputStream()
    DataOutputStream(bytes).use { out ->
      out.writeLong(entry.sequence)
      out.writeLong(entry.timeBucketHours)
      out.writeByte(entry.code.ordinal)
      out.writeByte(entry.fields.size)
      entry.fields.forEach { (key, value) ->
        writeShortUtf8(out, key)
        writeShortUtf8(out, value)
      }
    }
    return bytes.toByteArray()
  }

  private fun decodePayload(payload: ByteArray): SovereignRegistryEntry? {
    return try {
      DataInputStream(ByteArrayInputStream(payload)).use { input ->
        val sequence = input.readLong()
        val timeBucket = input.readLong()
        val ordinal = input.readUnsignedByte()
        val fieldCount = input.readUnsignedByte()
        if (sequence <= 0L || timeBucket < 0L || ordinal !in SovereignDiagnosticEventCode.entries.indices || fieldCount > 8) return@use null
        val fields = buildMap {
          repeat(fieldCount) { put(readShortUtf8(input), readShortUtf8(input)) }
        }
        if (input.available() != 0 || SovereignDiagnosticFieldPolicy.sanitize(fields) != fields) return@use null
        SovereignRegistryEntry(sequence, timeBucket, SovereignDiagnosticEventCode.entries[ordinal], fields)
      }
    } catch (_: Exception) {
      null
    }
  }

  private fun writeShortUtf8(out: DataOutputStream, value: String) {
    val bytes = value.toByteArray(StandardCharsets.UTF_8)
    require(bytes.size <= 96)
    out.writeByte(bytes.size)
    out.write(bytes)
  }

  private fun readShortUtf8(input: DataInputStream): String {
    val length = input.readUnsignedByte()
    require(length <= 96)
    return String(ByteArray(length).also(input::readFully), StandardCharsets.UTF_8)
  }

  private fun eventMac(token: String, payload: ByteArray, previous: ByteArray): ByteArray? {
    return try {
      val key = registryKey() ?: return null
      Mac.getInstance("HmacSHA256").run {
        init(key)
        update(domain)
        update(token.toByteArray(StandardCharsets.US_ASCII))
        update(previous)
        doFinal(payload)
      }
    } catch (_: Exception) {
      null
    }
  }

  private fun scopeToken(scope: Long?): String? {
    return try {
      val key = registryKey() ?: return null
      Mac.getInstance("HmacSHA256").run {
        init(key)
        update(scopeDomain)
        val value = scope ?: Long.MIN_VALUE
        doFinal(ByteBuffer.allocate(8).putLong(value).array()).copyOf(16).toHex()
      }
    } catch (_: Exception) {
      null
    }
  }

  private fun registryKey(): SecretKey? {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
    return try {
      KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore").run {
        init(
          KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setIsStrongBoxBacked(true)
            .build()
        )
        generateKey()
      }
    } catch (_: StrongBoxUnavailableException) {
      null
    } catch (_: Exception) {
      null
    }
  }

  private fun scopeFile(token: String): File =
    File(androidAppContext.noBackupFilesDir, "sovereign-registry/v1-$token.bin")

  private fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)

  private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

  private fun hexToBytes(value: String): ByteArray {
    require(value.length == 64)
    return ByteArray(32) { index -> value.substring(index * 2, index * 2 + 2).toInt(16).toByte() }
  }
}

actual fun platformSovereignRegistry(): SovereignRegistry = AndroidSovereignRegistry
