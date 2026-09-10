package com.maxrave.simpmusic.expect

import androidx.compose.runtime.Composable

/**
 * Reports whether the current device should use the tablet layout.
 *
 * This is deliberately platform-owned. Calling Material3 Adaptive's
 * currentWindowAdaptiveInfo() from the first iOS composition caused a
 * Kotlin/Native IrLinkageError in the device build, so the root composition
 * must not depend on that runtime path.
 */
@Composable
expect fun isTabletDevice(): Boolean
