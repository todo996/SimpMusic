package com.maxrave.simpmusic.expect

import androidx.compose.runtime.Composable
import platform.UIKit.UIDevice
import platform.UIKit.UIUserInterfaceIdiomPad

@Composable
actual fun isTabletDevice(): Boolean =
    UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
