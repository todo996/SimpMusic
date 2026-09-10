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


# 0) iOS 18 compatibility.
# Compose Multiplatform 1.11.x introduced a UIKit implementation that references
# UIViewLayoutRegion, an iOS 26 SDK symbol. That can be made to link with Xcode 26,
# but the resulting binary is not suitable for our iOS 16+ / iOS 18 device target.
# Pin the complete Compose stack to the last 1.10 generation instead. JetBrains'
# 1.10.3 release maps Material3 to 1.10.0-alpha05 and Adaptive to 1.3.0-alpha02.
versions = ROOT / "gradle/libs.versions.toml"

def patch_versions(text: str) -> str:
    replacements = {
        "composeMultiplatform": 'composeMultiplatform = "1.10.3" # iOS 18: avoid iOS-26-only UIViewLayoutRegion from Compose 1.11+',
        "componentsResources": 'componentsResources = "1.10.3" # keep resources aligned with Compose 1.10.3',
        "material3-multiplatform": 'material3-multiplatform = "1.10.0-alpha05" # official Material3 generation for Compose 1.10.3',
        "adaptive": 'adaptive = "1.3.0-alpha02" # official Material3 Adaptive generation for Compose 1.10.3',
        "compottie": 'compottie = "2.2.2" # stable build; do not pull Compose 1.12/Skiko snapshots into iOS',
    }
    for key, replacement in replacements.items():
        text = re.sub(
            rf'^{re.escape(key)}\s*=\s*"[^"]+".*$',
            replacement,
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

# 6) SharedViewModel file output must be KMP.
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

# Ensure Okio is directly available to composeApp commonMain and opt into the
# Material3 experimental APIs already used by the shared UI. Also enforce the
# complete Compose core generation at dependency-resolution time: version-catalog
# pins alone are not enough because libraries such as UI effects can request a
# newer Compose runtime transitively, and Gradle normally selects the highest
# requested version. That reintroduced UIViewLayoutRegion in run #36 even though
# the catalog had been rewritten to 1.10.3.
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

    guard_marker = "// iOS18_COMPOSE_RESOLUTION_GUARD"
    if guard_marker not in text:
        text += '''

// iOS18_COMPOSE_RESOLUTION_GUARD
// Keep transitive libraries from silently upgrading Compose to 1.11/1.12.
configurations.configureEach {
    resolutionStrategy.eachDependency {
        when (requested.group) {
            "org.jetbrains.compose.runtime",
            "org.jetbrains.compose.ui",
            "org.jetbrains.compose.foundation",
            "org.jetbrains.compose.animation",
            "org.jetbrains.compose.material" -> {
                useVersion("1.10.3")
                because("iOS 18 build must not resolve Compose 1.11+ UIKit runtime symbols")
            }
            "org.jetbrains.compose.material3" -> {
                useVersion("1.10.0-alpha05")
                because("Material3 generation compatible with Compose Multiplatform 1.10.3")
            }
            "org.jetbrains.compose.material3.adaptive" -> {
                useVersion("1.3.0-alpha02")
                because("Material3 Adaptive generation compatible with Compose Multiplatform 1.10.3")
            }
        }
    }
}
'''
    return text
rewrite(build, patch_build)

print(f"Prepared composeApp for iOS Native; rewrote {len(changed)} files")
for path in changed:
    print(f"  - {path}")

