package com.maxrave.simpmusic.extension

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import com.maxrave.domain.data.model.ui.ScreenSizeInfo
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.useContents
import platform.UIKit.UIApplication
import platform.UIKit.UIScreen

@OptIn(ExperimentalForeignApi::class)
@Composable
actual fun getScreenSizeInfo(): ScreenSizeInfo {
    val screen = UIScreen.mainScreen
    val scale = screen.scale
    val size = screen.bounds.useContents { size }
    val wDp = size.width.toInt()
    val hDp = size.height.toInt()
    return ScreenSizeInfo(
        hDP = hDp,
        wDP = wDp,
        hPX = (size.height * scale).toInt(),
        wPX = (size.width * scale).toInt(),
    )
}

@Composable
actual fun KeepScreenOn() {
    DisposableEffect(Unit) {
        UIApplication.sharedApplication.idleTimerDisabled = true
        onDispose {
            UIApplication.sharedApplication.idleTimerDisabled = false
        }
    }
}

@Composable
actual fun rememberIsInPipMode(): Boolean = false
