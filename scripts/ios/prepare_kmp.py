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

# 2) Use a published Compottie artifact for the Native CI path.
versions = ROOT / "gradle" / "libs.versions.toml"
t = versions.read_text()
t = t.replace('compottie = "2.2.2-compose-1.12-SNAPSHOT"', 'compottie = "2.2.2"')
versions.write_text(t)

core = ROOT / "core"
changed = []
removed = []

def rewrite(path: Path, transform):
    if not path.exists():
        return
    original = path.read_text()
    updated = transform(original)
    if updated != original:
        path.write_text(updated)
        changed.append(path.relative_to(ROOT).as_posix())

# 3) Common code must avoid JVM-only coroutine and Throwable APIs.
for p in core.rglob("*.kt"):
    if "src/commonMain/" not in p.as_posix():
        continue
    rewrite(
        p,
        lambda text: text.replace("Dispatchers.IO", "Dispatchers.Default").replace(".localizedMessage", ".message"),
    )

# 4) Normalize duplicated actual declarations. iosMain is the shared parent of
# iosArm64Main and iosSimulatorArm64Main, so duplicate target copies conflict.
ktor_ext = core / "service" / "ktorExt" / "src"
for source_set in ("iosArm64Main", "iosSimulatorArm64Main"):
    base = ktor_ext / source_set / "kotlin" / "com" / "maxrave" / "ktorext"
    for p in (
        base / f"Engine.{source_set.removesuffix('Main')}.kt",
        base / "encoding" / f"BrotliEncoder.{source_set.removesuffix('Main')}.kt",
    ):
        if p.exists():
            p.unlink()
            removed.append(p.relative_to(ROOT).as_posix())

# data has the same duplicate layout for the media loader/handler.
data_src = core / "data" / "src"
for source_set in ("iosArm64Main", "iosSimulatorArm64Main"):
    suffix = source_set.removesuffix("Main")
    for rel in (
        f"kotlin/com/maxrave/data/di/loader/Loader.{suffix}.kt",
        f"kotlin/com/maxrave/data/mediaservice/ExpectMediaHandler.{suffix}.kt",
    ):
        p = data_src / source_set / rel
        if p.exists():
            p.unlink()
            removed.append(p.relative_to(ROOT).as_posix())

# 5) kotlinYtmusicScraper/commonMain still contains JVM-only APIs. Replace the
# whole class of leaks here so Native compilation does not fail file-by-file.
scraper = core / "service" / "kotlinYtmusicScraper" / "src" / "commonMain" / "kotlin" / "com" / "maxrave" / "kotlinytmusicscraper"

quickjs = scraper / "cipher" / "QuickJsEngine.kt"
rewrite(
    quickjs,
    lambda text: text.replace(
        'append("\\\\u%04x".format(c.code))',
        'append("\\\\u" + c.code.toString(16).padStart(4, \'0\'))',
    ),
)

remote_store = scraper / "cipher" / "RemotePlayerConfigStore.kt"
rewrite(remote_store, lambda text: text.replace("    @Volatile\n", ""))

map_ext = scraper / "extension" / "MapExt.kt"
rewrite(
    map_ext,
    lambda _: """package com.maxrave.kotlinytmusicscraper.extension

inline fun <reified T : Any> T.asMap(): Map<String, Any?> = emptyMap()
""",
)

string_ext = scraper / "extension" / "StringExt.kt"
def patch_string_ext(text: str) -> str:
    text = text.replace("import java.security.MessageDigest\n", "import okio.ByteString.Companion.encodeUtf8\n")
    old_sha = '''fun String.sha256(): String {\n    val digest = MessageDigest.getInstance("SHA-256")\n    val hash = digest.digest(toByteArray())\n    return hash.fold("", { str, it -> str + "%02x".format(it) })\n}'''
    text = text.replace(old_sha, 'fun String.sha256(): String = encodeUtf8().sha256().hex()')
    return text
rewrite(string_ext, patch_string_ext)

utils = scraper / "utils" / "Utils.kt"
def patch_utils(text: str) -> str:
    text = text.replace("import java.security.MessageDigest\n", "import okio.ByteString.Companion.encodeUtf8\n")
    text = text.replace("import java.time.Instant\n", "import kotlin.time.Clock\n")
    text = text.replace(
        'fun ByteArray.toHex(): String = joinToString(separator = "") { eachByte -> "%02x".format(eachByte) }',
        'fun ByteArray.toHex(): String = joinToString(separator = "") { eachByte -> (eachByte.toInt() and 0xff).toString(16).padStart(2, \'0\') }',
    )
    text = text.replace(
        'fun sha1(str: String): String = MessageDigest.getInstance("SHA-1").digest(str.toByteArray()).toHex()',
        'fun sha1(str: String): String = str.encodeUtf8().sha1().hex()',
    )
    text = text.replace(
        'expirationTimeSeconds: Long = Instant.now().epochSecond + 86400 * 365,',
        'expirationTimeSeconds: Long = Clock.System.now().toEpochMilliseconds() / 1000 + 86400L * 365L,',
    )
    return text
rewrite(utils, patch_utils)

# 6) The data layer has JVM String.format leakage in commonMain.
for rel in (
    "data/src/commonMain/kotlin/com/maxrave/data/parser/search/SongResultParser.kt",
    "data/src/commonMain/kotlin/com/maxrave/data/parser/search/VideoResultParser.kt",
):
    p = core / rel
    rewrite(
        p,
        lambda text: text.replace(
            '"%02d:%02d".format(song.duration!! / 60, song.duration!! % 60)',
            'song.duration!!.let { duration -> "${(duration / 60).toString().padStart(2, \'0\')}:${(duration % 60).toString().padStart(2, \'0\')}" }',
        ),
    )

album_parser = core / "data/src/commonMain/kotlin/com/maxrave/data/parser/AlbumParser.kt"
rewrite(
    album_parser,
    lambda text: text.replace(
        '''"%02d:%02d".format(\n                            (songItem.duration ?: 0) / 60,\n                            (songItem.duration ?: 0) % 60,\n                        )''',
        '''(songItem.duration ?: 0).let { duration ->\n                            "${(duration / 60).toString().padStart(2, '0')}:${(duration % 60).toString().padStart(2, '0')}"\n                        }''',
    ),
)

# 7) Okio Sink/Source are Closeable in common code but not JVM AutoCloseable on Native.
message_codec = core / "service/listenTogether/src/commonMain/kotlin/org/simpmusic/listentogether/MessageCodec.kt"
def patch_message_codec(text: str) -> str:
    text = text.replace(
        '''        val sink = Buffer()\n        GzipSink(sink).buffer().use { it.write(data) }\n        return sink.readByteArray()''',
        '''        val sink = Buffer()\n        val gzipSink = GzipSink(sink).buffer()\n        try {\n            gzipSink.write(data)\n        } finally {\n            gzipSink.close()\n        }\n        return sink.readByteArray()''',
    )
    text = text.replace(
        '''        runCatching {\n            GzipSource(Buffer().apply { write(data) }).buffer().use { it.readByteArray() }\n        }.getOrNull()''',
        '''        runCatching {\n            val gzipSource = GzipSource(Buffer().apply { write(data) }).buffer()\n            try {\n                gzipSource.readByteArray()\n            } finally {\n                gzipSource.close()\n            }\n        }.getOrNull()''',
    )
    return text
rewrite(message_codec, patch_message_codec)

# 8) Room KMP requires a generated database constructor on non-Android targets.
music_db = core / "data/src/commonMain/kotlin/com/maxrave/data/db/MusicDatabase.kt"
def patch_room_database(text: str) -> str:
    if "import androidx.room.ConstructedBy\n" not in text:
        text = text.replace("import androidx.room.AutoMigration\n", "import androidx.room.AutoMigration\nimport androidx.room.ConstructedBy\n")
    if "import androidx.room.RoomDatabaseConstructor\n" not in text:
        text = text.replace("import androidx.room.RoomDatabase\n", "import androidx.room.RoomDatabase\nimport androidx.room.RoomDatabaseConstructor\n")
    marker = ")\n@TypeConverters(Converters::class)\nabstract class MusicDatabase"
    if "@ConstructedBy(MusicDatabaseConstructor::class)" not in text:
        text = text.replace(marker, ")\n@ConstructedBy(MusicDatabaseConstructor::class)\n@TypeConverters(Converters::class)\nabstract class MusicDatabase", 1)
    constructor = '''\n\n@Suppress("KotlinNoActualForExpect")\nexpect object MusicDatabaseConstructor : RoomDatabaseConstructor<MusicDatabase> {\n    override fun initialize(): MusicDatabase\n}\n'''
    if "expect object MusicDatabaseConstructor" not in text:
        text = text.replace("\nexpect fun getDatabaseBuilder(converters: Converters): RoomDatabase.Builder<MusicDatabase>\n", constructor + "\nexpect fun getDatabaseBuilder(converters: Converters): RoomDatabase.Builder<MusicDatabase>\n")
    return text
rewrite(music_db, patch_room_database)

print(f"Prepared iOS KMP build; rewrote {len(changed)} files")
for path in changed:
    print(f"  - {path}")
print(f"Removed {len(removed)} duplicated target-specific iOS actual files")
for path in removed:
    print(f"  - {path}")
