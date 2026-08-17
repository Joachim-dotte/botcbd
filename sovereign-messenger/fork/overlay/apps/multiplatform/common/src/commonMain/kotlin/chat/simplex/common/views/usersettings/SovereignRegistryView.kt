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
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import chat.simplex.common.model.ChatInfo
import chat.simplex.common.model.ChatModel
import chat.simplex.common.platform.ColumnWithScrollBar
import chat.simplex.common.sovereign.SovereignDiagnosticEventCode
import chat.simplex.common.sovereign.SovereignDiagnosticLog
import chat.simplex.common.sovereign.platformSovereignAttestationProvider
import chat.simplex.common.sovereign.platformSovereignRegistry
import chat.simplex.common.sovereign.sovereignAttestationLabel
import chat.simplex.common.sovereign.sovereignRegistryIntegrityLabel
import chat.simplex.common.views.chat.SovereignContactSecurityView
import chat.simplex.common.views.helpers.AppBarTitle
import chat.simplex.common.views.helpers.ModalManager
import chat.simplex.res.MR
import dev.icerock.moko.resources.compose.painterResource

/** Read-only view over the platform-authenticated local registry. */
@Composable
fun SovereignRegistryView(chatModel: ChatModel) {
  val contacts by remember {
    derivedStateOf {
      chatModel.chats.value
        .mapNotNull { (it.chatInfo as? ChatInfo.Direct)?.contact }
        .distinctBy { it.contactId }
    }
  }
  val provider = remember { platformSovereignAttestationProvider() }
  val registry = remember { platformSovereignRegistry() }
  val deviceRegistry by remember { registry.snapshot(null) }

  LaunchedEffect(Unit) {
    SovereignDiagnosticLog.append(SovereignDiagnosticEventCode.REGISTRY_OPENED)
    registry.append(null, SovereignDiagnosticEventCode.REGISTRY_OPENED)
  }

  ColumnWithScrollBar {
    AppBarTitle("Registre Sovereign")
    SectionView {
      SectionItemView {
        Column(Modifier.fillMaxWidth()) {
          Text("Integrite locale : ${sovereignRegistryIntegrityLabel(deviceRegistry.integrity)}")
          Text(
            "${deviceRegistry.entries.size} evenement(s), tete ${deviceRegistry.headFingerprint?.take(16) ?: "absente"}",
            color = MaterialTheme.colors.secondary,
            style = MaterialTheme.typography.body2,
          )
        }
      }
    }
    SectionTextFooter(
      "Le registre detecte les modifications locales avec une cle Keystore non exportable. " +
          "Une restauration complete vers un ancien snapshot exige encore un ancrage conserve par le pair."
    )
    SectionDividerSpaced()

    SectionView("Contacts") {
      if (contacts.isEmpty()) {
        SectionItemView { Text("Aucun contact disponible") }
      } else {
        contacts.forEach { contact ->
          val status by remember(contact.contactId) { provider.status(contact.contactId) }
          val contactRegistry by remember(contact.contactId) { registry.snapshot(contact.contactId) }
          SettingsActionItemWithContent(
            icon = painterResource(MR.images.ic_security),
            text = contact.displayName,
            click = {
              ModalManager.start.showModal(cardScreen = true) {
                SovereignContactSecurityView(contact)
              }
            },
          ) {
            Text(
              "${sovereignAttestationLabel(status.state)} · ${sovereignRegistryIntegrityLabel(contactRegistry.integrity)}",
              color = MaterialTheme.colors.secondary,
              style = MaterialTheme.typography.caption,
            )
          }
        }
      }
    }
    SectionBottomSpacer()
  }
}
