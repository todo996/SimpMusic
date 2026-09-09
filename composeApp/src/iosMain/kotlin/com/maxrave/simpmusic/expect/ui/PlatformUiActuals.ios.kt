package com.maxrave.simpmusic.expect.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import com.maxrave.domain.data.model.metadata.Lyrics
import com.maxrave.domain.data.model.streams.TimeLine

@Composable
actual fun PlatformCastButton(modifier: Modifier, tint: Color) = Unit

actual fun isPlatformCastAvailable(): Boolean = false

actual fun createWebViewCookieManager(): WebViewCookieManager =
    object : WebViewCookieManager {
        override fun getCookie(url: String): String = ""
        override fun removeAllCookies() = Unit
    }

@Composable
actual fun PlatformWebView(
    state: MutableState<WebViewState>,
    initUrl: String,
    aboveContent: @Composable (androidx.compose.foundation.layout.BoxScope.() -> Unit),
    onPageFinished: (String) -> Unit,
) {
    Box { aboveContent() }
    LaunchedEffect(initUrl) {
        state.value = WebViewState.Finished
        onPageFinished(initUrl)
    }
}

@Composable
actual fun DiscordWebView(
    state: MutableState<WebViewState>,
    aboveContent: @Composable (androidx.compose.foundation.layout.BoxScope.() -> Unit),
    onLoginDone: (token: String) -> Unit,
) {
    Box { aboveContent() }
}

@Composable
actual fun rememberDeviceVolumeController(): DeviceVolumeController? = null

private class IosFilePickerLauncher(
    private val callback: () -> Unit,
) : FilePickerLauncher {
    override fun launch() = callback()
}

@Composable
actual fun filePickerResult(
    mimeType: String,
    onResultUri: (String?) -> Unit,
): FilePickerLauncher = IosFilePickerLauncher { onResultUri(null) }

@Composable
actual fun fileSaverResult(
    fileName: String,
    mimeType: String,
    onResultUri: (String?) -> Unit,
): FilePickerLauncher = IosFilePickerLauncher { onResultUri(null) }

private class IosPhotoPickerLauncher(
    private val callback: () -> Unit,
) : PhotoPickerLauncher {
    override fun launch() = callback()
}

@Composable
actual fun photoPickerResult(onResultUri: (String?) -> Unit): PhotoPickerLauncher =
    IosPhotoPickerLauncher { onResultUri(null) }

actual fun isLyricsBlurSupported(): Boolean = true

@Composable
actual fun platformDynamicColorScheme(isDark: Boolean): ColorScheme? = null

actual fun isWallpaperDynamicColorSupported(): Boolean = false

@Composable
actual fun SystemBarAppearanceEffect(isDark: Boolean) = Unit

private class IosSaveImagePermissionRequester(
    private val onResult: (Boolean) -> Unit,
) : SaveImagePermissionRequester {
    override fun requestIfNeeded() = onResult(true)
}

@Composable
actual fun rememberSaveImagePermission(onResult: (granted: Boolean) -> Unit): SaveImagePermissionRequester =
    IosSaveImagePermissionRequester(onResult)

@Composable
actual fun HorizontalScrollBar(
    modifier: Modifier,
    scrollState: LazyListState,
) = Unit

@Composable
actual fun MediaPlayerView(
    url: String,
    modifier: Modifier,
    cropToBounds: Boolean,
) = Unit

@Composable
actual fun MediaPlayerViewWithSubtitle(
    modifier: Modifier,
    playerName: String,
    shouldPip: Boolean,
    shouldShowSubtitle: Boolean,
    shouldScaleDownSubtitle: Boolean,
    isInPipMode: Boolean,
    timelineState: TimeLine,
    lyricsData: Lyrics?,
    translatedLyricsData: Lyrics?,
    mainTextStyle: TextStyle,
    translatedTextStyle: TextStyle,
) = Unit
