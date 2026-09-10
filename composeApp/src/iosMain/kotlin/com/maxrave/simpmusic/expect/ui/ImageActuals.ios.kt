package com.maxrave.simpmusic.expect.ui

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asComposeImageBitmap
import androidx.compose.ui.graphics.asSkiaBitmap
import androidx.compose.ui.graphics.decodeToImageBitmap
import coil3.Image
import coil3.toBitmap
import okio.FileSystem
import okio.Path.Companion.toPath
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image as SkiaImage
import platform.Foundation.NSHomeDirectory

actual fun ImageBitmap.toByteArray(): ByteArray? =
    runCatching {
        SkiaImage
            .makeFromBitmap(asSkiaBitmap())
            .encodeToData(EncodedImageFormat.JPEG, 100)
            ?.bytes
    }.getOrNull()

actual fun ImageBitmap.toPngByteArray(): ByteArray? =
    runCatching {
        SkiaImage
            .makeFromBitmap(asSkiaBitmap())
            .encodeToData(EncodedImageFormat.PNG)
            ?.bytes
    }.getOrNull()

actual fun Image.toImageBitmap(): ImageBitmap =
    toBitmap().asComposeImageBitmap()

actual fun decodeImageBitmap(bytes: ByteArray): ImageBitmap? =
    runCatching {
        bytes.decodeToImageBitmap()
    }.getOrNull()

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
