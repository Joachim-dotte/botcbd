package chat.simplex.common.sovereign

import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf

/** Desktop has no device-attestation provider in this alpha. */
private object DesktopSovereignAttestationStub : SovereignAttestationProvider {
  private val notConfigured = mutableStateOf(SovereignAttestationStatus.notConfigured())

  override fun status(contactId: Long): State<SovereignAttestationStatus> = notConfigured

  override fun request(contactId: Long): SovereignAttestationRequestResult =
    SovereignAttestationRequestResult.ProviderNotConfigured
}

actual fun platformSovereignAttestationProvider(): SovereignAttestationProvider =
  DesktopSovereignAttestationStub
