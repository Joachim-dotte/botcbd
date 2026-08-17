package chat.simplex.common.sovereign

import androidx.compose.runtime.mutableStateListOf
import kotlinx.datetime.Clock

enum class SovereignDiagnosticEventCode {
  REGISTRY_OPENED,
  DEVELOPER_LOG_OPENED,
  CONTACT_SECURITY_OPENED,
  ATTESTATION_REQUESTED,
  ATTESTATION_RESULT,
}

data class SovereignDiagnosticEvent(
  val sequence: Long,
  val timestampEpochMillis: Long,
  val code: SovereignDiagnosticEventCode,
  val fields: Map<String, String>,
)

/**
 * Deny-by-default metadata policy. There is deliberately no free-text field,
 * contact identifier, user name, address, URI, message, token or exception text.
 */
object SovereignDiagnosticFieldPolicy {
  private val rules = mapOf(
    "result" to setOf("OK", "NOT_CONFIGURED", "PENDING", "VERIFIED", "REJECTED", "EXPIRED", "ERROR"),
    "reason_code" to setOf("NONE", "PROVIDER_NOT_CONFIGURED", "KEY_UNAVAILABLE", "NO_LOCAL_RESULT", "REQUEST_ACCEPTED", "LOCAL_QR_BASIC", "LOCAL_QR_STRONG", "POLICY_REJECTED", "EVIDENCE_EXPIRED"),
    "security_level" to setOf("UNKNOWN", "ATTENTION", "VERIFIED"),
    "attestation_state" to setOf("NOT_CONFIGURED", "NOT_CHECKED", "PENDING", "VERIFIED_LOCAL_BASIC", "VERIFIED_LOCAL_STRONG", "VERIFIED", "REJECTED", "EXPIRED"),
  )

  fun sanitize(rawFields: Map<String, String>): Map<String, String> = buildMap {
    rawFields.forEach { (key, value) ->
      if (rules[key]?.contains(value) == true) put(key, value)
    }
  }
}

class SovereignDiagnosticEventBuffer(
  private val capacity: Int = 128,
  private val nowEpochMillis: () -> Long = { Clock.System.now().toEpochMilliseconds() },
) {
  init {
    require(capacity in 1..1024) { "capacity must be between 1 and 1024" }
  }

  private val entries = mutableListOf<SovereignDiagnosticEvent>()
  private var nextSequence = 1L

  fun append(code: SovereignDiagnosticEventCode, rawFields: Map<String, String> = emptyMap()) {
    if (entries.size == capacity) entries.removeAt(0)
    entries.add(
      SovereignDiagnosticEvent(
        sequence = nextSequence++,
        timestampEpochMillis = nowEpochMillis(),
        code = code,
        fields = SovereignDiagnosticFieldPolicy.sanitize(rawFields),
      )
    )
  }

  fun snapshot(): List<SovereignDiagnosticEvent> = entries.toList()

  fun clear() {
    entries.clear()
  }
}

/**
 * UI-owned, bounded, memory-only journal. Do not bridge android.util.Log or the
 * existing SimpleX debug logger into this object: those streams can contain
 * protocol payloads.
 */
object SovereignDiagnosticLog {
  private val buffer = SovereignDiagnosticEventBuffer()
  private val observableEntries = mutableStateListOf<SovereignDiagnosticEvent>()

  val events: List<SovereignDiagnosticEvent> get() = observableEntries

  fun append(code: SovereignDiagnosticEventCode, fields: Map<String, String> = emptyMap()) {
    buffer.append(code, fields)
    observableEntries.clear()
    observableEntries.addAll(buffer.snapshot())
  }

  fun clear() {
    buffer.clear()
    observableEntries.clear()
  }
}
