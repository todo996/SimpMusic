package com.maxrave.simpmusic.expect

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration

@Composable
actual fun isTabletDevice(): Boolean =
    LocalConfiguration.current.smallestScreenWidthDp >= 600
