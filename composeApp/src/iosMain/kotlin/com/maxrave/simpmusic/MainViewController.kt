package com.maxrave.simpmusic

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.ComposeUIViewController
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
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

/**
 * iOS has no Activity/Fragment to provide a ViewModelStoreOwner to Compose.
 * Navigation Compose reads LocalViewModelStoreOwner as soon as NavHost enters
 * composition, so provide one explicitly for the lifetime of the root controller.
 */
private object IosRootViewModelStoreOwner : ViewModelStoreOwner {
    override val viewModelStore: ViewModelStore = ViewModelStore()
}

private fun iosComposeController(content: @Composable () -> Unit) =
    ComposeUIViewController {
        CompositionLocalProvider(
            LocalViewModelStoreOwner provides IosRootViewModelStoreOwner,
        ) {
            content()
        }
    }

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
        iosComposeController {
            StartupFailureScreen(startupFailure.message ?: "Unknown startup error")
        }
    } else {
        println("SimpMusic iOS startup: Koin ready")
        val readyViewModel = requireNotNull(rootViewModel)
        iosComposeController {
            App(viewModel = readyViewModel)
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
