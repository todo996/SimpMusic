from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "composeApp"
COMMON = APP / "src/commonMain/kotlin"
changed = []


def rewrite(path: Path, transform):
    if not path.exists():
        return
    original = path.read_text()
    updated = transform(original)
    if updated != original:
        path.write_text(updated)
        changed.append(path.relative_to(ROOT).as_posix())


# 0) Keep the iOS Compose runtime on the same generation as the Compose plugin.
# Compose Multiplatform 1.11.1 does NOT publish Material3 as 1.11.1. JetBrains'
# compatibility table maps it to Material3 1.11.0-alpha07 and Material3 Adaptive
# 1.3.0-alpha07. The upstream catalog pins Material3 1.12.0-alpha01, which
# transitively upgrades foundation/ui + Skiko to the Compose 1.12 line and makes
# the produced framework reference newer Apple SDK symbols (UIViewLayoutRegion /
# SwiftUICore) that Xcode 16.4 cannot link. Use the official 1.11 generation
# coordinates and stable Compottie, which stays on the matching Skiko line.
versions = ROOT / "gradle/libs.versions.toml"

def patch_versions(text: str) -> str:
    text = re.sub(
        r'^material3-multiplatform\s*=\s*"[^"]+".*$',
        'material3-multiplatform = "1.11.0-alpha07" # iOS CI: official Material3 for Compose Multiplatform 1.11.1',
        text,
        flags=re.M,
    )
    text = re.sub(
        r'^adaptive\s*=\s*"[^"]+".*$',
        'adaptive = "1.3.0-alpha07" # iOS CI: official Material3 Adaptive for Compose Multiplatform 1.11.1',
        text,
        flags=re.M,
    )
    text = re.sub(
        r'^compottie\s*=\s*"[^"]+".*$',
        'compottie = "2.2.2" # iOS CI: stable build matching the Compose 1.11 Skiko line',
        text,
        flags=re.M,
    )
    return text

rewrite(versions, patch_versions)

# 1) Common Kotlin/Native cleanup applied across composeApp/commonMain.
for p in COMMON.rglob("*.kt"):
    def normalize(text: str) -> str:
        text = text.replace("Dispatchers.IO", "Dispatchers.Default")
        text = text.replace("System.currentTimeMillis()", "kotlin.time.Clock.System.now().toEpochMilliseconds()")
        text = text.replace("import androidx.compose.ui.graphics.asImageBitmap\n", "")
        text = text.replace("Character.isWhitespace(it)", "it.isWhitespace()")
        text = text.replace(".removeIf {", ".removeAll {")
        return text
    rewrite(p, normalize)

# 2) commonMain must not call java.lang.System for desktop metadata.
platform = COMMON / "com/maxrave/simpmusic/Platform.kt"
rewrite(
    platform,
    lambda text: text.replace(
        'Desktop -> System.getProperty("os.name") ?: "jvm"',
        'Desktop -> "jvm"',
    ),
)

# 3) AllExt mixes pure common utilities with unused JVM-only File/ZIP helpers.
# Keep the portable utilities and remove the unused JVM-only helpers from the iOS build.
all_ext = COMMON / "com/maxrave/simpmusic/extension/AllExt.kt"

def patch_all_ext(text: str) -> str:
    for line in (
        "import java.io.File\n",
        "import java.io.InputStream\n",
        "import java.io.OutputStream\n",
        "import java.util.Locale\n",
        "import java.util.concurrent.TimeUnit\n",
        "import java.util.zip.ZipInputStream\n",
        "import java.util.zip.ZipOutputStream\n",
    ):
        text = text.replace(line, "")

    text = re.sub(
        r'''@Composable\nfun formatDuration\(duration: Long\): String \{.*?\n\}''',
        '''@Composable\nfun formatDuration(duration: Long): String {\n    if (duration < 0L) return stringResource(Res.string.na_na)\n    val totalSeconds = duration / 1000L\n    val minutes = totalSeconds / 60L\n    val seconds = totalSeconds % 60L\n    return "${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"\n}''',
        text,
        count=1,
        flags=re.S,
    )

    text = re.sub(
        r'''\nfun InputStream\.zipInputStream\(\): ZipInputStream = ZipInputStream\(this\)\n\nfun OutputStream\.zipOutputStream\(\): ZipOutputStream = ZipOutputStream\(this\)\n''',
        "\n",
        text,
        count=1,
    )
    text = re.sub(
        r'''\nfun getSizeOfFile\(dir: File\): Long \{.*?\n\}\n''',
        "\n",
        text,
        count=1,
        flags=re.S,
    )
    return text

rewrite(all_ext, patch_all_ext)

# 4) Replace java.time formatting in settings with kotlinx-datetime.
settings = COMMON / "com/maxrave/simpmusic/ui/screen/home/SettingScreen.kt"

def patch_settings(text: str) -> str:
    text = text.replace("import java.time.Instant\n", "")
    text = text.replace("import java.time.ZoneId\n", "")
    text = text.replace("import java.time.format.DateTimeFormatter\n", "")

    if "import kotlinx.datetime.TimeZone\n" not in text:
        anchor = "import kotlinx.datetime.LocalDateTime\n"
        if anchor in text:
            text = text.replace(anchor, anchor + "import kotlinx.datetime.TimeZone\n", 1)
        else:
            text = text.replace("package com.maxrave.simpmusic.ui.screen.home\n", "package com.maxrave.simpmusic.ui.screen.home\n\nimport kotlinx.datetime.TimeZone\n", 1)
    if "import kotlinx.datetime.toLocalDateTime\n" not in text:
        anchor = "import kotlinx.datetime.TimeZone\n"
        text = text.replace(anchor, anchor + "import kotlinx.datetime.toLocalDateTime\n", 1)

    old = '''DateTimeFormatter\n                            .ofPattern("yyyy-MM-dd HH:mm:ss")\n                            .withZone(ZoneId.systemDefault())\n                            .format(Instant.ofEpochMilli(lastCheckLong))'''
    new = '''kotlinx.datetime.Instant\n                            .fromEpochMilliseconds(lastCheckLong)\n                            .toLocalDateTime(TimeZone.currentSystemDefault())\n                            .format(LocalDateTime.Format { byUnicodePattern("yyyy-MM-dd HH:mm:ss") })'''
    text = text.replace(old, new)

    old2 = '''DateTimeFormatter\n                                            .ofPattern("yyyy-MM-dd HH:mm:ss")\n                                            .withZone(ZoneId.systemDefault())\n                                            .format(Instant.ofEpochMilli(autoBackupLastTime))'''
    new2 = '''kotlinx.datetime.Instant\n                                            .fromEpochMilliseconds(autoBackupLastTime)\n                                            .toLocalDateTime(TimeZone.currentSystemDefault())\n                                            .format(LocalDateTime.Format { byUnicodePattern("yyyy-MM-dd HH:mm:ss") })'''
    text = text.replace(old2, new2)
    return text

rewrite(settings, patch_settings)

# 5) JVM formatting helpers used only for presentation.
modal = COMMON / "com/maxrave/simpmusic/ui/component/ModalBottomSheet.kt"
rewrite(
    modal,
    lambda text: text.replace(
        'text = "x${String.format("%.1f", playbackSpeed)}",',
        'text = "x$playbackSpeed",',
    ),
)

for rel in (
    "com/maxrave/simpmusic/ui/screen/player/content/NowPlayingContentSpotify.kt",
    "com/maxrave/simpmusic/ui/screen/player/content/NowPlayingExpressiveCards.kt",
):
    p = COMMON / rel
    rewrite(
        p,
        lambda text: text.replace(
            '"%,d".format(state.screenData.songInfoData?.viewCount)',
            '(state.screenData.songInfoData?.viewCount ?: 0).toString()',
        ),
    )

# 6) SharedViewModel file output must be KMP. Okio is already versioned by the project.
shared = COMMON / "com/maxrave/simpmusic/viewModel/SharedViewModel.kt"

def patch_shared(text: str) -> str:
    text = text.replace("import java.io.FileOutputStream\n", "")
    if "import okio.FileSystem\n" not in text:
        text = text.replace("import org.jetbrains.compose.resources.getString\n", "import org.jetbrains.compose.resources.getString\nimport okio.FileSystem\nimport okio.Path.Companion.toPath\n")
    old = '''                    val fileOutputStream = FileOutputStream("$path.jpg")\n                    fileOutputStream.write(bytesArray)\n                    fileOutputStream.close()'''
    new = '''                    if (bytesArray != null) {\n                        FileSystem.SYSTEM.write("$path.jpg".toPath()) { write(bytesArray) }\n                    }'''
    text = text.replace(old, new)
    return text

rewrite(shared, patch_shared)

# Ensure Okio is directly available to composeApp commonMain and opt the Native
# compile into both standard and Expressive Material3 experimental APIs used by
# the shared UI. MaterialExpressiveTheme and LinearWavyProgressIndicator use
# ExperimentalMaterial3ExpressiveApi, not ExperimentalMaterial3Api.
build = APP / "build.gradle.kts"
def patch_build(text: str) -> str:
    if "implementation(libs.okio)" not in text:
        marker = "            implementation(libs.kotlinx.serialization.json)\n"
        if marker in text:
            text = text.replace(marker, marker + "            implementation(libs.okio)\n", 1)
        else:
            marker = "            implementation(libs.ktor.client.cio)\n"
            text = text.replace(marker, marker + "            implementation(libs.okio)\n", 1)

    opt_ins = (
        '        freeCompilerArgs.add("-opt-in=androidx.compose.material3.ExperimentalMaterial3Api")\n',
        '        freeCompilerArgs.add("-opt-in=androidx.compose.material3.ExperimentalMaterial3ExpressiveApi")\n',
    )
    marker = '        freeCompilerArgs.add("-Xexpect-actual-classes")\n'
    for opt_in in opt_ins:
        if opt_in not in text and marker in text:
            text = text.replace(marker, marker + opt_in, 1)
    return text
rewrite(build, patch_build)

print(f"Prepared composeApp for iOS Native; rewrote {len(changed)} files")
for path in changed:
    print(f"  - {path}")
