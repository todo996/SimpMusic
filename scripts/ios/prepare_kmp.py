from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# 1) Enable the iOS targets in composeApp for this branch build.
build = ROOT / "composeApp" / "build.gradle.kts"
s = build.read_text()
old = """//    listOf(\n//        iosArm64(),\n//        iosSimulatorArm64()\n//    ).forEach { iosTarget ->\n//        iosTarget.binaries.framework {\n//            baseName = \"ComposeApp\"\n//            isStatic = true\n//        }\n//    }"""
new = """    listOf(\n        iosArm64(),\n        iosSimulatorArm64()\n    ).forEach { iosTarget ->\n        iosTarget.binaries.framework {\n            baseName = \"ComposeApp\"\n            isStatic = true\n        }\n    }"""
if old in s:
    s = s.replace(old, new)
elif new not in s:
    raise SystemExit("Unable to locate composeApp iOS target block")

# Android/JVM-only libraries must not leak into Native compilation.
s = s.replace("            implementation(libs.ui.tooling.preview)\n", "")
s = s.replace("            api(libs.coil.network.okhttp)\n", "")
build.write_text(s)

# 2) The repository currently pins a Compose-specific Compottie snapshot that is
# unavailable on GitHub's macOS runner. Use the published artifact for Native CI.
versions = ROOT / "gradle" / "libs.versions.toml"
t = versions.read_text()
t = t.replace('compottie = "2.2.2-compose-1.12-SNAPSHOT"', 'compottie = "2.2.2"')
versions.write_text(t)

# 3) kotlinx.coroutines does not expose Dispatchers.IO on Kotlin/Native in the
# version used by this project. The core submodule uses it throughout commonMain.
# Normalize ALL commonMain usages in one pass instead of chasing compiler errors
# file-by-file. Android/JVM source sets remain untouched and keep Dispatchers.IO.
changed = []
core = ROOT / "core"
for p in core.rglob("*.kt"):
    if "src/commonMain/" not in p.as_posix():
        continue
    text = p.read_text()
    if "Dispatchers.IO" not in text:
        continue
    updated = text.replace("Dispatchers.IO", "Dispatchers.Default")
    p.write_text(updated)
    changed.append(p.relative_to(ROOT).as_posix())

# 4) core/service/ktorExt currently declares the same iOS actuals at two levels:
# iosMain and the concrete iosArm64Main/iosSimulatorArm64Main source sets. Kotlin
# Native merges iosMain into each target, so those declarations conflict. Keep
# the shared iosMain implementations and remove the target-specific duplicates.
# This is a source-set structural normalization for both simulator and device.
removed = []
ktor_ext = core / "service" / "ktorExt" / "src"
for source_set in ("iosArm64Main", "iosSimulatorArm64Main"):
    base = ktor_ext / source_set / "kotlin" / "com" / "maxrave" / "ktorext"
    candidates = [
        base / f"Engine.{source_set.removesuffix('Main')}.kt",
        base / "encoding" / f"BrotliEncoder.{source_set.removesuffix('Main')}.kt",
    ]
    for p in candidates:
        if p.exists():
            p.unlink()
            removed.append(p.relative_to(ROOT).as_posix())

print(f"Prepared iOS KMP build; normalized {len(changed)} commonMain files")
for path in changed:
    print(f"  - {path}")
print(f"Removed {len(removed)} duplicated target-specific iOS actual files")
for path in removed:
    print(f"  - {path}")
