package com.maxrave.simpmusic.expect.ui

import androidx.compose.ui.graphics.ImageBitmap
import coil3.Image
import okio.FileSystem
import okio.Path.Companion.toPath
import platform.Foundation.NSHomeDirectory

actual fun ImageBitmap.toByteArray(): ByteArray? = null

actual fun ImageBitmap.toPngByteArray(): ByteArray? = null

actual fun Image.toImageBitmap(): ImageBitmap =
    error("Coil image conversion is not available on iOS yet")

actual fun decodeImageBitmap(bytes: ByteArray): ImageBitmap? = null

actual suspend fun persistPickedImage(
    bytes: ByteArray,
    fileName: String,
): String? =
    runCatching {
        val dir = "${NSHomeDirectory()}/Documents/SimpMusicImages".toPath()
        FileSystem.SYSTEM.createDirectories(dir)
        val path = dir / fileName
        FileSystem.SYSTEM.write(path) { write(bytes) }
        "file://${path}"
    }.getOrNull()
