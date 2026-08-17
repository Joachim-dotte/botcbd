package chat.simplex.common.sovereign

import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf

private object DesktopSovereignRegistry : SovereignRegistry {
  private val unsupported = mutableStateOf(SovereignRegistrySnapshot.unsupported())

  override fun snapshot(scope: Long?): State<SovereignRegistrySnapshot> = unsupported

  override fun append(
    scope: Long?,
    code: SovereignDiagnosticEventCode,
    rawFields: Map<String, String>,
  ): Boolean = false

  override fun refresh(scope: Long?) = Unit
}

actual fun platformSovereignRegistry(): SovereignRegistry = DesktopSovereignRegistry

