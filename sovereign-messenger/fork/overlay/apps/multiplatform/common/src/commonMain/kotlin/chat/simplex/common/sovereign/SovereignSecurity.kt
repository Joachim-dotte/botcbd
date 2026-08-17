package chat.simplex.common.sovereign

/**
 * Device-attestation state as understood by the UI layer.
 *
 * VERIFIED is reserved for a future provider which also binds a fresh challenge
 * to the already verified SimpleX contact transcript. The local QR provider can
 * return the two explicitly separate VERIFIED_LOCAL_* states only.
 */
enum class SovereignAttestationState {
  NOT_CONFIGURED,
  NOT_CHECKED,
  PENDING,
  VERIFIED_LOCAL_BASIC,
  VERIFIED_LOCAL_STRONG,
  VERIFIED,
  REJECTED,
  EXPIRED,
}

data class SovereignAttestationStatus(
  val state: SovereignAttestationState,
  val checkedAtEpochMillis: Long? = null,
  val reason: SovereignAttestationReason = SovereignAttestationReason.NONE,
) {
  companion object {
    fun notConfigured() = SovereignAttestationStatus(
      state = SovereignAttestationState.NOT_CONFIGURED,
      reason = SovereignAttestationReason.PROVIDER_NOT_CONFIGURED,
    )

    fun keyUnavailable() = SovereignAttestationStatus(
      state = SovereignAttestationState.NOT_CONFIGURED,
      reason = SovereignAttestationReason.KEY_UNAVAILABLE,
    )

    fun notChecked() = SovereignAttestationStatus(
      state = SovereignAttestationState.NOT_CHECKED,
      reason = SovereignAttestationReason.NO_LOCAL_RESULT,
    )
  }
}

enum class SovereignAttestationReason {
  NONE,
  PROVIDER_NOT_CONFIGURED,
  KEY_UNAVAILABLE,
  NO_LOCAL_RESULT,
  REQUEST_ACCEPTED,
  LOCAL_QR_BASIC,
  LOCAL_QR_STRONG,
  POLICY_REJECTED,
  EVIDENCE_EXPIRED,
}

sealed interface SovereignAttestationRequestResult {
  data object ProviderNotConfigured : SovereignAttestationRequestResult
  data object Started : SovereignAttestationRequestResult
}

/**
 * Integration seam for a future Android attestation implementation.
 * Contact identifiers must never be written to [SovereignDiagnosticLog].
 */
interface SovereignAttestationProvider {
  fun status(contactId: Long): androidx.compose.runtime.State<SovereignAttestationStatus>
  fun request(contactId: Long): SovereignAttestationRequestResult
}

expect fun platformSovereignAttestationProvider(): SovereignAttestationProvider

enum class ConversationSecurityLevel {
  UNKNOWN,
  ATTENTION,
  VERIFIED,
}

enum class ConversationSecurityBlocker {
  SAFETY_CODE_NOT_VERIFIED,
  POST_QUANTUM_NOT_ENABLED,
  ATTESTATION_NOT_CONFIGURED,
  ATTESTATION_NOT_CHECKED,
  ATTESTATION_PENDING,
  ATTESTATION_NOT_BOUND_TO_CONTACT,
  ATTESTATION_REJECTED,
  ATTESTATION_EXPIRED,
}

data class ConversationSecurityInput(
  val safetyCodeVerified: Boolean,
  val postQuantumEnabled: Boolean,
  val attestationState: SovereignAttestationState,
)

data class ConversationSecuritySummary(
  val level: ConversationSecurityLevel,
  val blockers: Set<ConversationSecurityBlocker>,
)

/**
 * Fail-closed aggregation. VERIFIED requires every independent signal.
 * UNKNOWN is used only when attestation is the sole missing/pending signal;
 * an explicit negative signal always produces ATTENTION.
 */
fun aggregateConversationSecurity(input: ConversationSecurityInput): ConversationSecuritySummary {
  val blockers = buildSet {
    if (!input.safetyCodeVerified) add(ConversationSecurityBlocker.SAFETY_CODE_NOT_VERIFIED)
    if (!input.postQuantumEnabled) add(ConversationSecurityBlocker.POST_QUANTUM_NOT_ENABLED)
    when (input.attestationState) {
      SovereignAttestationState.NOT_CONFIGURED -> add(ConversationSecurityBlocker.ATTESTATION_NOT_CONFIGURED)
      SovereignAttestationState.NOT_CHECKED -> add(ConversationSecurityBlocker.ATTESTATION_NOT_CHECKED)
      SovereignAttestationState.PENDING -> add(ConversationSecurityBlocker.ATTESTATION_PENDING)
      SovereignAttestationState.VERIFIED_LOCAL_BASIC,
      SovereignAttestationState.VERIFIED_LOCAL_STRONG ->
        add(ConversationSecurityBlocker.ATTESTATION_NOT_BOUND_TO_CONTACT)
      SovereignAttestationState.REJECTED -> add(ConversationSecurityBlocker.ATTESTATION_REJECTED)
      SovereignAttestationState.EXPIRED -> add(ConversationSecurityBlocker.ATTESTATION_EXPIRED)
      SovereignAttestationState.VERIFIED -> Unit
    }
  }

  val onlyUnknownAttestation = blockers.isNotEmpty() && blockers.all {
    it == ConversationSecurityBlocker.ATTESTATION_NOT_CONFIGURED ||
        it == ConversationSecurityBlocker.ATTESTATION_NOT_CHECKED ||
        it == ConversationSecurityBlocker.ATTESTATION_PENDING
  }
  val level = when {
    blockers.isEmpty() -> ConversationSecurityLevel.VERIFIED
    onlyUnknownAttestation -> ConversationSecurityLevel.UNKNOWN
    else -> ConversationSecurityLevel.ATTENTION
  }
  return ConversationSecuritySummary(level, blockers)
}

fun sovereignAttestationLabel(state: SovereignAttestationState): String = when (state) {
  SovereignAttestationState.NOT_CONFIGURED -> "NON CONFIGURÉ"
  SovereignAttestationState.NOT_CHECKED -> "NON CONTRÔLÉ"
  SovereignAttestationState.PENDING -> "EN ATTENTE"
  SovereignAttestationState.VERIFIED_LOCAL_BASIC -> "QR LOCAL BASIQUE"
  SovereignAttestationState.VERIFIED_LOCAL_STRONG -> "QR LOCAL FORT"
  SovereignAttestationState.VERIFIED -> "VÉRIFIÉ"
  SovereignAttestationState.REJECTED -> "REJETÉ"
  SovereignAttestationState.EXPIRED -> "EXPIRÉ"
}

fun sovereignSecurityLevelLabel(level: ConversationSecurityLevel): String = when (level) {
  ConversationSecurityLevel.UNKNOWN -> "INCONNU"
  ConversationSecurityLevel.ATTENTION -> "ATTENTION"
  ConversationSecurityLevel.VERIFIED -> "VÉRIFIÉ"
}
