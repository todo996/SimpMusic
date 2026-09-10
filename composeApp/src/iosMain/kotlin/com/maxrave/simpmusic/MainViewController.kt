package com.maxrave.simpmusic

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.ComposeUIViewController
import com.maxrave.common.AppIdentity
import com.maxrave.data.di.loader.loadAllModules
import com.maxrave.domain.manager.DataStoreManager
import com.maxrave.domain.mediaservice.handler.MediaPlayerHandler
import com.maxrave.domain.repository.AlbumRepository
import com.maxrave.domain.repository.CacheRepository
import com.maxrave.domain.repository.LyricsCanvasRepository
import com.maxrave.domain.repository.LocalPlaylistRepository
import com.maxrave.domain.repository.PlaylistRepository
import com.maxrave.domain.repository.SongRepository
import com.maxrave.domain.repository.StreamRepository
import com.maxrave.domain.repository.UpdateRepository
import com.maxrave.simpmusic.viewModel.SharedViewModel
import org.koin.core.context.loadKoinModules
import org.koin.core.context.startKoin
import org.koin.mp.KoinPlatform.getKoin
import platform.UIKit.UIDevice

fun MainViewController() = run {
    println("SimpMusic iOS startup: initializing Koin")
    var rootViewModel: SharedViewModel? = null
    val startupFailure =
        runCatching {
            initializeIosApp()
            // Resolve the root graph before Compose starts. This keeps missing iOS bindings visible
            // with a concrete dependency path instead of an opaque composition failure.
            preflightIosGraph()
            // Resolve this outside Compose as well. Calling koinInject() from the first iOS
            // composition used to cross the Koin-Compose ABI boundary before any UI was drawn.
            rootViewModel = getKoin().get()
        }.exceptionOrNull()

    if (startupFailure != null) {
        println("SimpMusic iOS startup failed: ${startupFailure.stackTraceToString()}")
        // A dependency failure must not turn into an immediate process termination on a physical
        // device. Keep the process alive and show a small diagnostic surface so the device log can
        // be collected and the exact missing binding can be fixed. This surface deliberately does
        // not inject Koin or read resources, so it remains available when graph construction fails.
        ComposeUIViewController {
            StartupFailureScreen(startupFailure.message ?: "Unknown startup error")
        }
    } else {
        println("SimpMusic iOS startup: Koin ready")
        val readyViewModel = requireNotNull(rootViewModel)
        ComposeUIViewController {
            // Keep a Native linkage failure visible on-device instead of letting an exception
            // escape the first composition and terminate the process with SIGABRT.
            try {
                App(viewModel = readyViewModel)
            } catch (failure: Throwable) {
                println("SimpMusic iOS Compose startup failed: ${failure.stackTraceToString()}")
                StartupFailureScreen(failure.message ?: "Compose initialization error")
            }
        }
    }
}

@Composable
private fun StartupFailureScreen(message: String) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("SimpMusic không thể khởi động")
        Text(message)
    }
}

private fun preflightIosGraph() {
    resolveIosDependency<DataStoreManager>("DataStoreManager")
    resolveIosDependency<MediaPlayerHandler>("MediaPlayerHandler")
    resolveIosDependency<StreamRepository>("StreamRepository")
    resolveIosDependency<UpdateRepository>("UpdateRepository")
    resolveIosDependency<SongRepository>("SongRepository")
    resolveIosDependency<AlbumRepository>("AlbumRepository")
    resolveIosDependency<LocalPlaylistRepository>("LocalPlaylistRepository")
    resolveIosDependency<PlaylistRepository>("PlaylistRepository")
    resolveIosDependency<LyricsCanvasRepository>("LyricsCanvasRepository")
    resolveIosDependency<CacheRepository>("CacheRepository")
}

private inline fun <reified T : Any> resolveIosDependency(label: String) {
    println("SimpMusic iOS startup: resolving $label")
    getKoin().get<T>()
    println("SimpMusic iOS startup: $label ready")
}

private var iosAppInitialized = false

/** Starts the KMP graph before Compose evaluates a screen that calls koinInject(). */
private fun initializeIosApp() {
    if (iosAppInitialized) return
    iosAppInitialized = true
    startKoin {
        loadAllModules(
            AppIdentity(
                applicationId = "com.maxrave.simpmusic.ios",
                versionName = BuildKonfig.versionName,
                platform = "iOS ${UIDevice.currentDevice.systemVersion}",
            ),
        )
        loadKoinModules(com.maxrave.simpmusic.di.viewModelModule)
    }
}
