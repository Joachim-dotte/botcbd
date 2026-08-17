package chat.simplex.common.views.chat

import SectionBottomSpacer
import SectionDividerSpaced
import InfoRow
import SectionItemView
import SectionTextFooter
import SectionView
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.Icon
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import chat.simplex.common.model.Contact
import chat.simplex.common.platform.ColumnWithScrollBar
import chat.simplex.common.sovereign.ConversationSecurityInput
import chat.simplex.common.sovereign.ConversationSecurityLevel
import chat.simplex.common.sovereign.SovereignAttestationRequestResult
import chat.simplex.common.sovereign.SovereignAttestationState
import chat.simplex.common.sovereign.SovereignDiagnosticEventCode
import chat.simplex.common.sovereign.SovereignDiagnosticLog
import chat.simplex.common.sovereign.aggregateConversationSecurity
import chat.simplex.common.sovereign.platformSovereignAttestationProvider
import chat.simplex.common.sovereign.platformSovereignRegistry
import chat.simplex.common.sovereign.sovereignAttestationLabel
import chat.simplex.common.sovereign.sovereignRegistryIntegrityLabel
import chat.simplex.common.sovereign.sovereignSecurityLevelLabel
import chat.simplex.common.views.helpers.AlertManager
import chat.simplex.common.views.helpers.AppBarTitle
import chat.simplex.common.views.helpers.ModalManager
import chat.simplex.common.views.usersettings.SettingsActionItem
import chat.simplex.res.MR
import dev.icerock.moko.resources.compose.painterResource

@Composable
fun SovereignContactSecurityView(contact: Contact) {
  val provider = remember { platformSovereignAttestationProvider() }
  val registry = remember { platformSovereignRegistry() }
  val registrySnapshot by remember(contact.contactId) { registry.snapshot(contact.contactId) }
  val status by remember(contact.contactId) { provider.status(contact.contactId) }
  val summary = aggregateConversationSecurity(
    ConversationSecurityInput(
      safetyCodeVerified = contact.verified,
      postQuantumEnabled = contact.activeConn?.connPQEnabled == true,
      attestationState = status.state,
    )
  )

  LaunchedEffect(contact.contactId, summary.level, status.state) {
    SovereignDiagnosticLog.append(
      SovereignDiagnosticEventCode.CONTACT_SECURITY_OPENED,
      mapOf(
        "security_level" to summary.level.name,
        "attestation_state" to status.state.name,
      ),
    )
    registry.append(
      contact.contactId,
      SovereignDiagnosticEventCode.CONTACT_SECURITY_OPENED,
      mapOf(
        "security_level" to summary.level.name,
        "attestation_state" to status.state.name,
      ),
    )
  }

  LaunchedEffect(contact.contactId, status.state, status.reason) {
    val terminalResult = when (status.state) {
      SovereignAttestationState.VERIFIED_LOCAL_BASIC,
      SovereignAttestationState.VERIFIED_LOCAL_STRONG,
      SovereignAttestationState.VERIFIED -> "VERIFIED"
      SovereignAttestationState.REJECTED -> "REJECTED"
      SovereignAttestationState.EXPIRED -> "EXPIRED"
      SovereignAttestationState.NOT_CONFIGURED,
      SovereignAttestationState.NOT_CHECKED,
      SovereignAttestationState.PENDING -> null
    }
    if (terminalResult != null) {
      val fields = mapOf("result" to terminalResult, "reason_code" to status.reason.name)
      val alreadyRecorded = registrySnapshot.entries
        .lastOrNull { it.code == SovereignDiagnosticEventCode.ATTESTATION_RESULT }
        ?.fields == fields
      if (!alreadyRecorded) {
        SovereignDiagnosticLog.append(SovereignDiagnosticEventCode.ATTESTATION_RESULT, fields)
        registry.append(contact.contactId, SovereignDiagnosticEventCode.ATTESTATION_RESULT, fields)
      }
    }
  }

  ColumnWithScrollBar {
    AppBarTitle("Securite de la conversation")
    SectionView {
      InfoRow("Synthese", sovereignSecurityLevelLabel(summary.level))
      InfoRow("Code de securite SimpleX", if (contact.verified) "VERIFIE" else "NON VERIFIE")
      InfoRow(
        "Chiffrement post-quantique",
        if (contact.activeConn?.connPQEnabled == true) "ACTIF" else "NON ACTIF",
      )
      InfoRow("Attestation appareil", sovereignAttestationLabel(status.state))
      InfoRow("Registre local", sovereignRegistryIntegrityLabel(registrySnapshot.integrity))
      InfoRow("Evenements verifies", registrySnapshot.entries.size.toString())
    }
    SectionTextFooter(
      "Cette synthese est fail-closed. Une preuve QR locale reste orange tant qu'elle n'est pas liee " +
          "cryptographiquement au code de securite SimpleX verifie."
    )
    SectionDividerSpaced()
    SectionView("Journal de preuve") {
      if (registrySnapshot.entries.isEmpty()) {
        SectionItemView { Text("Aucun evenement enregistre") }
      } else {
        registrySnapshot.entries.takeLast(20).asReversed().forEach { event ->
          SectionItemView {
            Column(Modifier.fillMaxWidth()) {
              Text("#${event.sequence} ${event.code.name}")
              Text(
                event.fields.entries.joinToString("  ") { "${it.key}=${it.value}" }
                  .ifEmpty { "aucune metadonnee" },
                color = MaterialTheme.colors.secondary,
                style = MaterialTheme.typography.caption,
              )
            }
          }
        }
      }
    }
    SectionTextFooter("Heure arrondie, aucun texte de message, nom, adresse, URI ou certificat brut.")
    SectionDividerSpaced()
    SectionView {
      SettingsActionItem(
        painterResource(MR.images.ic_security),
        "Demander une attestation",
        click = {
          SovereignDiagnosticLog.append(SovereignDiagnosticEventCode.ATTESTATION_REQUESTED)
          registry.append(contact.contactId, SovereignDiagnosticEventCode.ATTESTATION_REQUESTED)
          when (provider.request(contact.contactId)) {
            SovereignAttestationRequestResult.ProviderNotConfigured -> {
              SovereignDiagnosticLog.append(
                SovereignDiagnosticEventCode.ATTESTATION_RESULT,
                mapOf(
                  "result" to "NOT_CONFIGURED",
                  "reason_code" to "PROVIDER_NOT_CONFIGURED",
                ),
              )
              registry.append(
                contact.contactId,
                SovereignDiagnosticEventCode.ATTESTATION_RESULT,
                mapOf("result" to "NOT_CONFIGURED", "reason_code" to "PROVIDER_NOT_CONFIGURED"),
              )
              AlertManager.shared.showAlertMsg(
                title = "Attestation non configuree",
                text = "Point d'appel present, mais aucun challenge ni aucune preuve cryptographique ne sont implementes dans cet alpha.",
              )
            }
            SovereignAttestationRequestResult.Started -> {
              SovereignDiagnosticLog.append(
                SovereignDiagnosticEventCode.ATTESTATION_RESULT,
                mapOf("result" to "PENDING", "reason_code" to "REQUEST_ACCEPTED"),
              )
              registry.append(
                contact.contactId,
                SovereignDiagnosticEventCode.ATTESTATION_RESULT,
                mapOf("result" to "PENDING", "reason_code" to "REQUEST_ACCEPTED"),
              )
            }
          }
        },
      )
    }
    SectionBottomSpacer()
  }
}

@Composable
fun SovereignConversationSecurityButton(contact: Contact) {
  SettingsActionItem(
    painterResource(MR.images.ic_security),
    "Securite Sovereign",
    click = {
      ModalManager.end.showModal(cardScreen = true) {
        SovereignContactSecurityView(contact)
      }
    },
  )
}

@Composable
fun SovereignConversationBadge(contact: Contact) {
  val provider = remember { platformSovereignAttestationProvider() }
  val status by remember(contact.contactId) { provider.status(contact.contactId) }
  val level = aggregateConversationSecurity(
    ConversationSecurityInput(
      safetyCodeVerified = contact.verified,
      postQuantumEnabled = contact.activeConn?.connPQEnabled == true,
      attestationState = status.state,
    )
  ).level
  val tint = when (level) {
    ConversationSecurityLevel.VERIFIED -> MaterialTheme.colors.secondary
    ConversationSecurityLevel.ATTENTION -> MaterialTheme.colors.error
    ConversationSecurityLevel.UNKNOWN -> Color.Gray
  }
  val honestTint = when (status.state) {
    chat.simplex.common.sovereign.SovereignAttestationState.VERIFIED_LOCAL_BASIC,
    chat.simplex.common.sovereign.SovereignAttestationState.VERIFIED_LOCAL_STRONG -> Color(0xFFFFA000)
    else -> tint
  }
  Icon(
    painterResource(MR.images.ic_security),
    contentDescription = "Etat Sovereign : ${sovereignSecurityLevelLabel(level)}",
    modifier = Modifier.padding(end = 3.dp),
    tint = honestTint,
  )
}
