package com.maxrave.simpmusic.expect

import okio.FileSystem
import okio.Path.Companion.toPath
import platform.Foundation.NSHomeDirectory

actual suspend fun saveImageToDevice(
    bytes: ByteArray,
    fileName: String,
): Boolean =
    runCatching {
        val dir = "${NSHomeDirectory()}/Documents".toPath()
        FileSystem.SYSTEM.createDirectories(dir)
        FileSystem.SYSTEM.write(dir / fileName) { write(bytes) }
        true
    }.getOrDefault(false)

actual suspend fun shareImage(
    bytes: ByteArray,
    fileName: String,
    chooserTitle: String,
): Boolean = saveImageToDevice(bytes, fileName)
