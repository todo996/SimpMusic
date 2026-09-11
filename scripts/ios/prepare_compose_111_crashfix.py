from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
VERSIONS = ROOT / "gradle/libs.versions.toml"
BUILD = ROOT / "composeApp/build.gradle.kts"


def replace_version(text: str, key: str, value: str, comment: str = "") -> str:
    suffix = f" # {comment}" if comment else ""
    replacement = f'{key} = "{value}"{suffix}'
    updated, count = re.subn(
        rf'^{re.escape(key)}\s*=\s*"[^"]+".*$',
        replacement,
        text,
        flags=re.M,
    )
    if count != 1:
        raise SystemExit(f"Expected exactly one version entry for {key}, found {count}")
    return updated


# The previous iOS workaround forced Compose 1.10.3 / Skiko 0.9.x while the
# current app libraries (Coil 3.5.0, Compottie 2.2.2 and Markdown) were compiled
# against the Compose 1.11 / Skia M144 generation. That produces Kotlin/Native
# IrLinkageError stubs (Painter$stableprop_getter, drawImageRect, Shader, PathBuilder).
# Restore one coherent ABI generation instead of mixing KLIB generations.
versions = VERSIONS.read_text()
for key, value, comment in (
    ("composeMultiplatform", "1.11.1", "ABI generation used by Coil 3.5.0"),
    ("componentsResources", "1.11.1", "match Compose runtime/UI"),
    ("material3-multiplatform", "1.11.0-alpha07", "official Material3 for Compose 1.11.1"),
    ("adaptive", "1.3.0-alpha07", "official Material3 Adaptive for Compose 1.11.1"),
    ("coil3", "3.5.0", "compiled with Compose 1.11.1 and Skiko 0.144.6"),
    ("compottie", "2.2.2", "stable M144-compatible generation"),
):
    versions = replace_version(versions, key, value, comment)
VERSIONS.write_text(versions)

build = BUILD.read_text()
old_marker = "// iOS18_COMPOSE_RESOLUTION_GUARD"
pos = build.find(old_marker)
if pos >= 0:
    # prepare_compose_kmp.py appends the old 1.10.x resolution guard at EOF.
    build = build[:pos].rstrip() + "\n"

build += r'''

// IOS_COMPOSE_111_ABI_GUARD_20260911
// Keep every Compose family on the same ABI generation. Do not let transitive
// libraries upgrade to Compose 1.12 or downgrade to 1.10 independently.
configurations.configureEach {
    resolutionStrategy.eachDependency {
        when (requested.group) {
            "org.jetbrains.compose.runtime",
            "org.jetbrains.compose.ui",
            "org.jetbrains.compose.foundation",
            "org.jetbrains.compose.animation",
            "org.jetbrains.compose.material" -> {
                useVersion("1.11.1")
                because("iOS crash fix: one Compose 1.11.1 ABI generation")
            }
            "org.jetbrains.compose.material3" -> {
                useVersion("1.11.0-alpha07")
                because("official Material3 generation for Compose Multiplatform 1.11.1")
            }
            "org.jetbrains.compose.material3.adaptive" -> {
                useVersion("1.3.0-alpha07")
                because("official Material3 Adaptive generation for Compose 1.11.1")
            }
            "org.jetbrains.skiko" -> {
                useVersion("0.144.6")
                because("Compose 1.11.1 / Coil 3.5.0 use Skia M144 ABI")
            }
            "org.jetbrains.compose.components" -> {
                useVersion("1.11.1")
                because("Compose resources must match Compose 1.11.1")
            }
        }
    }
}
'''
BUILD.write_text(build)

print("Applied iOS crash-fix dependency alignment:")
print("  Compose Multiplatform 1.11.1")
print("  Material3 1.11.0-alpha07")
print("  Adaptive 1.3.0-alpha07")
print("  Skiko 0.144.6")
print("  Coil 3.5.0")
print("  Compottie 2.2.2")
