package chat.simplex.common.sovereign

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StructuredDiagnosticLogTest {
  @Test
  fun policyDropsUnknownAndSensitiveFields() {
    val sanitized = SovereignDiagnosticFieldPolicy.sanitize(
      mapOf(
        "result" to "NOT_CONFIGURED",
        "security_level" to "UNKNOWN",
        "token" to "secret-token",
        "message" to "private message",
        "contact_id" to "42",
        "uri" to "simplex:/contact-link",
      )
    )

    assertEquals(
      mapOf("result" to "NOT_CONFIGURED", "security_level" to "UNKNOWN"),
      sanitized,
    )
    val rendered = sanitized.toString()
    assertFalse("secret-token" in rendered)
    assertFalse("private message" in rendered)
    assertFalse("42" in rendered)
    assertFalse("simplex:/" in rendered)
  }

  @Test
  fun policyDropsMalformedValuesEvenForAllowedKeys() {
    val sanitized = SovereignDiagnosticFieldPolicy.sanitize(
      mapOf(
        "result" to "OK private payload",
        "reason_code" to "contains lowercase",
        "age_seconds" to "-1",
        "count" to "1",
      )
    )

    assertTrue(sanitized.isEmpty())
  }

  @Test
  fun bufferIsBoundedAndKeepsOnlySanitizedMetadata() {
    var now = 100L
    val buffer = SovereignDiagnosticEventBuffer(capacity = 2) { now++ }
    buffer.append(SovereignDiagnosticEventCode.REGISTRY_OPENED)
    buffer.append(
      SovereignDiagnosticEventCode.ATTESTATION_REQUESTED,
      mapOf("result" to "PENDING", "message" to "must disappear"),
    )
    buffer.append(
      SovereignDiagnosticEventCode.ATTESTATION_RESULT,
      mapOf("result" to "NOT_CONFIGURED"),
    )

    val snapshot = buffer.snapshot()
    assertEquals(2, snapshot.size)
    assertEquals(2L, snapshot.first().sequence)
    assertEquals(mapOf("result" to "PENDING"), snapshot.first().fields)
    assertFalse("must disappear" in snapshot.toString())
  }
}
