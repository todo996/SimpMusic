package com.maxrave.simpmusic

import androidx.compose.ui.window.ComposeUIViewController
import com.maxrave.common.AppIdentity
import com.maxrave.data.di.loader.loadAllModules
import org.koin.core.context.loadKoinModules
import org.koin.core.context.startKoin
import platform.UIKit.UIDevice

fun MainViewController() = run {
    initializeIosApp()
    ComposeUIViewController { App() }
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
