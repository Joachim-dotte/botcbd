package chat.simplex.common.views.usersettings

import SectionBottomSpacer
import SectionDividerSpaced
import SectionItemView
import SectionTextFooter
import SectionView
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import chat.simplex.common.platform.ColumnWithScrollBar
import chat.simplex.common.sovereign.SovereignDiagnosticEventCode
import chat.simplex.common.sovereign.SovereignDiagnosticLog
import chat.simplex.common.sovereign.platformSovereignRegistry
import chat.simplex.common.sovereign.sovereignRegistryIntegrityLabel
import chat.simplex.common.views.helpers.AppBarTitle
import chat.simplex.res.MR
import dev.icerock.moko.resources.compose.painterResource

@Composable
fun SovereignDiagnosticLogView() {
  val events = SovereignDiagnosticLog.events
  val registry = remember { platformSovereignRegistry() }
  val persistent by remember { registry.snapshot(null) }

  LaunchedEffect(Unit) {
    SovereignDiagnosticLog.append(SovereignDiagnosticEventCode.DEVELOPER_LOG_OPENED)
    registry.append(null, SovereignDiagnosticEventCode.DEVELOPER_LOG_OPENED)
  }

  ColumnWithScrollBar {
    AppBarTitle("Journal structure Sovereign")
    SectionView("Registre persistant authentifie") {
      SectionItemView {
        Column(Modifier.fillMaxWidth()) {
          Text("Integrite : ${sovereignRegistryIntegrityLabel(persistent.integrity)}")
          Text(
            "${persistent.entries.size} evenement(s), tete ${persistent.headFingerprint?.take(16) ?: "absente"}",
            color = MaterialTheme.colors.secondary,
            style = MaterialTheme.typography.caption,
          )
        }
      }
      persistent.entries.takeLast(32).asReversed().forEach { event ->
        SectionItemView {
          Column(Modifier.fillMaxWidth()) {
            Text("#${event.sequence} ${event.code.name}")
            Text(
              event.fields.entries.joinToString(separator = "  ") { "${it.key}=${it.value}" }
                .ifEmpty { "aucune metadonnee" },
              color = MaterialTheme.colors.secondary,
              style = MaterialTheme.typography.caption,
            )
          }
        }
      }
    }
    SectionTextFooter(
      "Chaine SHA-256 + HMAC Keystore StrongBox, heures arrondies, aucun contenu de message ni identifiant en clair."
    )
    SectionDividerSpaced()
    SectionView("Flux volatile de cette session") {
      if (events.isEmpty()) {
        SectionItemView { Text("Aucun evenement") }
      } else {
        events.toList().asReversed().forEach { event ->
          SectionItemView {
            Column(Modifier.fillMaxWidth()) {
              Text("#${event.sequence} ${event.code.name}")
              Text(
                event.fields.entries.joinToString(separator = "  ") { "${it.key}=${it.value}" }
                  .ifEmpty { "aucune metadonnee" },
                color = MaterialTheme.colors.secondary,
                style = MaterialTheme.typography.caption,
              )
            }
          }
        }
      }
    }
    SectionTextFooter(
      "Champs allowlistes : aucun message, contact, URI, jeton, certificat ou payload."
    )
    if (events.isNotEmpty()) {
      SectionDividerSpaced()
      SectionView {
        SettingsActionItem(
          painterResource(MR.images.ic_delete),
          "Effacer le journal",
          SovereignDiagnosticLog::clear,
        )
      }
    }
    SectionBottomSpacer()
  }
}
