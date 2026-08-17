package chat.simplex.common.sovereign

import androidx.compose.runtime.State

enum class SovereignRegistryIntegrity {
  VALID,
  EMPTY,
  TAMPERED,
  KEY_UNAVAILABLE,
  UNSUPPORTED,
}

data class SovereignRegistryEntry(
  val sequence: Long,
  val timeBucketHours: Long,
  val code: SovereignDiagnosticEventCode,
  val fields: Map<String, String>,
)

data class SovereignRegistrySnapshot(
  val integrity: SovereignRegistryIntegrity,
  val entries: List<SovereignRegistryEntry> = emptyList(),
  val headFingerprint: String? = null,
) {
  companion object {
    fun unsupported() = SovereignRegistrySnapshot(SovereignRegistryIntegrity.UNSUPPORTED)
  }
}

/**
 * Persistent, content-free security registry. A null scope is the device scope;
 * a non-null scope is mapped to an opaque platform token before storage.
 */
interface SovereignRegistry {
  fun snapshot(scope: Long?): State<SovereignRegistrySnapshot>
  fun append(
    scope: Long?,
    code: SovereignDiagnosticEventCode,
    rawFields: Map<String, String> = emptyMap(),
  ): Boolean
  fun refresh(scope: Long?)
}

expect fun platformSovereignRegistry(): SovereignRegistry

fun sovereignRegistryIntegrityLabel(value: SovereignRegistryIntegrity): String = when (value) {
  SovereignRegistryIntegrity.VALID -> "VALIDE"
  SovereignRegistryIntegrity.EMPTY -> "VIDE"
  SovereignRegistryIntegrity.TAMPERED -> "ALTERE"
  SovereignRegistryIntegrity.KEY_UNAVAILABLE -> "CLE INDISPONIBLE"
  SovereignRegistryIntegrity.UNSUPPORTED -> "NON SUPPORTE"
}
