package chat.simplex.common.sovereign

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SovereignSecurityTest {
  @Test
  fun verifiedRequiresEverySignal() {
    val summary = aggregateConversationSecurity(
      ConversationSecurityInput(
        safetyCodeVerified = true,
        postQuantumEnabled = true,
        attestationState = SovereignAttestationState.VERIFIED,
      )
    )

    assertEquals(ConversationSecurityLevel.VERIFIED, summary.level)
    assertTrue(summary.blockers.isEmpty())
  }

  @Test
  fun notConfiguredIsUnknownWhenOtherSignalsPass() {
    val summary = aggregateConversationSecurity(
      ConversationSecurityInput(
        safetyCodeVerified = true,
        postQuantumEnabled = true,
        attestationState = SovereignAttestationState.NOT_CONFIGURED,
      )
    )

    assertEquals(ConversationSecurityLevel.UNKNOWN, summary.level)
    assertEquals(
      setOf(ConversationSecurityBlocker.ATTESTATION_NOT_CONFIGURED),
      summary.blockers,
    )
  }

  @Test
  fun pendingNeverBecomesVerified() {
    val summary = aggregateConversationSecurity(
      ConversationSecurityInput(
        safetyCodeVerified = true,
        postQuantumEnabled = true,
        attestationState = SovereignAttestationState.PENDING,
      )
    )

    assertEquals(ConversationSecurityLevel.UNKNOWN, summary.level)
    assertTrue(ConversationSecurityBlocker.ATTESTATION_PENDING in summary.blockers)
  }

  @Test
  fun localQrProofIsNotMisrepresentedAsContactBound() {
    val summary = aggregateConversationSecurity(
      ConversationSecurityInput(
        safetyCodeVerified = true,
        postQuantumEnabled = true,
        attestationState = SovereignAttestationState.VERIFIED_LOCAL_STRONG,
      )
    )

    assertEquals(ConversationSecurityLevel.ATTENTION, summary.level)
    assertEquals(
      setOf(ConversationSecurityBlocker.ATTESTATION_NOT_BOUND_TO_CONTACT),
      summary.blockers,
    )
  }

  @Test
  fun anyExplicitNegativeSignalNeedsAttention() {
    val noSafetyCode = aggregateConversationSecurity(
      ConversationSecurityInput(false, true, SovereignAttestationState.NOT_CONFIGURED)
    )
    val noPostQuantum = aggregateConversationSecurity(
      ConversationSecurityInput(true, false, SovereignAttestationState.PENDING)
    )
    val rejected = aggregateConversationSecurity(
      ConversationSecurityInput(true, true, SovereignAttestationState.REJECTED)
    )
    val expired = aggregateConversationSecurity(
      ConversationSecurityInput(true, true, SovereignAttestationState.EXPIRED)
    )

    assertEquals(ConversationSecurityLevel.ATTENTION, noSafetyCode.level)
    assertEquals(ConversationSecurityLevel.ATTENTION, noPostQuantum.level)
    assertEquals(ConversationSecurityLevel.ATTENTION, rejected.level)
    assertEquals(ConversationSecurityLevel.ATTENTION, expired.level)
  }
}
