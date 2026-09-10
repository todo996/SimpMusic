package com.maxrave.simpmusic.viewModel

import com.eygraber.uri.Uri
import com.maxrave.domain.repository.CacheRepository
import com.maxrave.domain.repository.CommonRepository
import platform.Foundation.NSHomeDirectory

actual suspend fun calculateDataFraction(cacheRepository: CacheRepository): SettingsStorageSectionFraction? = null

actual suspend fun restoreNative(
    commonRepository: CommonRepository,
    uri: Uri,
    getData: () -> Unit,
) {
    getData()
}

actual suspend fun backupNative(
    commonRepository: CommonRepository,
    uri: Uri,
    backupDownloaded: Boolean,
) = Unit

actual fun getPackageName(): String = "com.maxrave.simpmusic.ios"

actual fun getFileDir(): String = NSHomeDirectory() + "/Documents"

actual fun changeLanguageNative(code: String) = Unit

