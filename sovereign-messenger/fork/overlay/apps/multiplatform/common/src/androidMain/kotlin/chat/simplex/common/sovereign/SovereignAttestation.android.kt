package chat.simplex.common.sovereign

import android.app.Activity
import android.app.Application
import android.content.pm.PackageManager
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import app.attestation.auditor.SovereignAuditorAlpha
import chat.simplex.common.platform.androidAppContext
import chat.simplex.common.platform.mainActivity
import java.nio.ByteBuffer
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

private object AndroidSovereignAttestationProvider :
  SovereignAttestationProvider,
  Application.ActivityLifecycleCallbacks {

  private const val SCOPE_HMAC_ALIAS = "sovereign_simplex_contact_scope_hmac_v1"
  private const val MAXIMUM_RESULT_AGE_MILLIS = 24L * 60L * 60L * 1000L
  private val scopeDomain = "SimpleX/Sovereign/local-attestation/contact-scope/v1"
    .encodeToByteArray()
  private val keyLock = Any()
  private val scopedStates = mutableMapOf<String, ScopedState>()
  private val unsupported = mutableStateOf(SovereignAttestationStatus.notConfigured())
  private val keyUnavailable = mutableStateOf(SovereignAttestationStatus.keyUnavailable())
  private var callbacksRegistered = false

  private data class ScopedState(
    val token: ByteArray,
    val state: MutableState<SovereignAttestationStatus>,
  )

  override fun status(contactId: Long): State<SovereignAttestationStatus> {
    if (!SovereignAuditorAlpha.isSupported()) return unsupported
    ensureCallbacks()
    val token = scopeToken(contactId) ?: return keyUnavailable
    return scopedState(token).state
  }

  override fun request(contactId: Long): SovereignAttestationRequestResult {
    if (!SovereignAuditorAlpha.isSupported()) {
      return SovereignAttestationRequestResult.ProviderNotConfigured
    }
    val activity = mainActivity.get()
      ?: return SovereignAttestationRequestResult.ProviderNotConfigured
    ensureCallbacks()
    val token = scopeToken(contactId)
      ?: return SovereignAttestationRequestResult.ProviderNotConfigured
    val scoped = scopedState(token)
    scoped.state.value = SovereignAttestationStatus(
      state = SovereignAttestationState.PENDING,
      checkedAtEpochMillis = System.currentTimeMillis(),
      reason = SovereignAttestationReason.REQUEST_ACCEPTED,
    )
    return try {
      activity.startActivity(SovereignAuditorAlpha.createIntent(activity, token))
      SovereignAttestationRequestResult.Started
    } catch (_: RuntimeException) {
      scoped.state.value = readStatus(token)
      SovereignAttestationRequestResult.ProviderNotConfigured
    }
  }

  private fun scopedState(token: ByteArray): ScopedState {
    val mapKey = Base64.encodeToString(
      token,
      Base64.NO_WRAP or Base64.NO_PADDING or Base64.URL_SAFE,
    )
    return scopedStates.getOrPut(mapKey) {
      val isolatedToken = token.copyOf()
      ScopedState(isolatedToken, mutableStateOf(readStatus(isolatedToken)))
    }
  }

  private fun readStatus(token: ByteArray): SovereignAttestationStatus {
    val cached = SovereignAuditorAlpha.readStatus(androidAppContext, token)
    if (cached.verdict() == SovereignAuditorAlpha.Verdict.NONE) {
      return SovereignAttestationStatus.notChecked()
    }
    if (!cached.isFresh(MAXIMUM_RESULT_AGE_MILLIS)) {
      return SovereignAttestationStatus(
        state = SovereignAttestationState.EXPIRED,
        checkedAtEpochMillis = cached.updatedAtEpochMillis(),
        reason = SovereignAttestationReason.EVIDENCE_EXPIRED,
      )
    }
    return when (cached.verdict()) {
      SovereignAuditorAlpha.Verdict.VERIFIED_BASIC -> SovereignAttestationStatus(
        state = SovereignAttestationState.VERIFIED_LOCAL_BASIC,
        checkedAtEpochMillis = cached.updatedAtEpochMillis(),
        reason = SovereignAttestationReason.LOCAL_QR_BASIC,
      )
      SovereignAuditorAlpha.Verdict.VERIFIED_STRONG -> SovereignAttestationStatus(
        state = SovereignAttestationState.VERIFIED_LOCAL_STRONG,
        checkedAtEpochMillis = cached.updatedAtEpochMillis(),
        reason = SovereignAttestationReason.LOCAL_QR_STRONG,
      )
      SovereignAuditorAlpha.Verdict.REJECTED -> SovereignAttestationStatus(
        state = SovereignAttestationState.REJECTED,
        checkedAtEpochMillis = cached.updatedAtEpochMillis(),
        reason = SovereignAttestationReason.POLICY_REJECTED,
      )
      SovereignAuditorAlpha.Verdict.NONE -> SovereignAttestationStatus.notChecked()
    }
  }

  private fun scopeToken(contactId: Long): ByteArray? = try {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(getOrCreateScopeKey())
    mac.update(scopeDomain)
    mac.doFinal(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(contactId).array())
  } catch (_: Exception) {
    // Fail closed without logging the contact identifier, token, alias material or exception text.
    null
  }

  private fun getOrCreateScopeKey(): SecretKey = synchronized(keyLock) {
    if (!androidAppContext.packageManager.hasSystemFeature(
        PackageManager.FEATURE_STRONGBOX_KEYSTORE
      )) {
      throw GeneralSecurityException("StrongBox is not available")
    }
    val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    val key = (keyStore.getKey(SCOPE_HMAC_ALIAS, null) as? SecretKey)
      ?: generateScopeKey()
    requireStrongBox(key)
  }

  private fun generateScopeKey(): SecretKey {
    val generator = KeyGenerator.getInstance(
      KeyProperties.KEY_ALGORITHM_HMAC_SHA256,
      "AndroidKeyStore",
    )
    val specification = KeyGenParameterSpec.Builder(
      SCOPE_HMAC_ALIAS,
      KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
    )
      .setDigests(KeyProperties.DIGEST_SHA256)
      .setKeySize(256)
      .setUnlockedDeviceRequired(true)
      .setIsStrongBoxBacked(true)
      .build()
    generator.init(specification)
    return generator.generateKey()
  }

  private fun requireStrongBox(key: SecretKey): SecretKey {
    val factory = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
    val keyInfo = factory.getKeySpec(key, KeyInfo::class.java) as? KeyInfo
      ?: throw GeneralSecurityException("scope key metadata is unavailable")
    if (keyInfo.securityLevel != KeyProperties.SECURITY_LEVEL_STRONGBOX) {
      throw GeneralSecurityException("scope key is not StrongBox-backed")
    }
    return key
  }

  private fun ensureCallbacks() {
    if (callbacksRegistered) return
    val application = androidAppContext.applicationContext as? Application ?: return
    application.registerActivityLifecycleCallbacks(this)
    callbacksRegistered = true
  }

  private fun refreshScopedStates() {
    scopedStates.values.forEach { scoped -> scoped.state.value = readStatus(scoped.token) }
  }

  override fun onActivityResumed(activity: Activity) {
    if (activity === mainActivity.get()) refreshScopedStates()
  }

  override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
  override fun onActivityStarted(activity: Activity) = Unit
  override fun onActivityPaused(activity: Activity) = Unit
  override fun onActivityStopped(activity: Activity) = Unit
  override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
  override fun onActivityDestroyed(activity: Activity) = Unit
}

actual fun platformSovereignAttestationProvider(): SovereignAttestationProvider =
  AndroidSovereignAttestationProvider
