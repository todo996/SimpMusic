package com.maxrave.simpmusic.expect

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.useContents
import platform.Foundation.NSHomeDirectory
import platform.Foundation.NSURL
import platform.UIKit.UIApplication
import platform.UIKit.UIPasteboard
import platform.UIKit.UIScreen

actual fun copyToClipboard(label: String, text: String) {
    UIPasteboard.generalPasteboard.string = text
}

actual fun getDownloadFolderPath(): String = NSHomeDirectory() + "/Documents"

actual fun openUrl(url: String) {
    val nsUrl = NSURL.URLWithString(url) ?: return
    UIApplication.sharedApplication.openURL(
        nsUrl,
        options = emptyMap<Any?, Any>(),
        completionHandler = null,
    )
}

actual fun shareUrl(title: String, url: String) {
    openUrl(url)
}

@OptIn(ExperimentalForeignApi::class)
actual fun currentOrientation(): Orientation {
    val bounds = UIScreen.mainScreen.bounds
    return bounds.useContents {
        when {
            size.width > size.height -> Orientation.LANDSCAPE
            size.height > size.width -> Orientation.PORTRAIT
            else -> Orientation.UNSPECIFIED
        }
    }
}

