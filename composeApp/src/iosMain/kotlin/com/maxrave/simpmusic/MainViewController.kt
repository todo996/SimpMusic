package com.maxrave.simpmusic

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
    initializeIosApp()
    // Resolve the root graph before Compose starts. This keeps missing iOS bindings visible as a
    // launch error with a concrete dependency path instead of an opaque composition failure.
    try {
        preflightIosGraph()
        getKoin().get<SharedViewModel>()
    } catch (error: Throwable) {
        // Kotlin/Native otherwise only prints Koin's outer InstanceCreationException before
        // terminating the process. Keep the complete cause chain in the simulator/device log so
        // a sideload launch failure can be fixed from evidence rather than guessed at.
        println("SimpMusic iOS startup failed: ${error.stackTraceToString()}")
        throw error
    }
    println("SimpMusic iOS startup: Koin ready")
    ComposeUIViewController { App() }
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

