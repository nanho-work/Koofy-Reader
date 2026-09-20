@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)

package com.koofy.reader.bridge

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.css.FontStyle
import org.readium.r2.navigator.epub.css.FontWeight
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.data.Container
import org.readium.r2.shared.util.file.FileResource
import org.readium.r2.shared.util.resource.Resource

/** Verified local font files, independent of the source that supplied them. */
internal class ReaderFonts(context: Context, downloadedDirectory: File? = null) {
    data class Face(val file: File, val weight: Int, val href: Url)
    data class Family(val id: String, val label: String, val cssFamily: String, val faces: List<Face>)
    val families: List<Family>

    init {
        val directory = File(context.filesDir, "reader-fonts/v1")
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create font storage" }
        val catalog = JSONObject(context.assets.open("catalog.json").bufferedReader().use { it.readText() })
        check(catalog.getInt("version") == 1)
        val entries = catalog.getJSONArray("families")
        val bundled = (0 until entries.length()).map { index ->
            val item = entries.getJSONObject(index)
            val faces = item.getJSONArray("faces")
            Family(item.getString("id"), item.getString("label"), item.getString("cssFamily"),
                (0 until faces.length()).map { faceIndex ->
                    val face = faces.getJSONObject(faceIndex)
                    val hash = face.getString("sha256")
                    check(hash.matches(Regex("[a-f0-9]{64}")))
                    val file = File(directory, "$hash.otf")
                    if (!file.isFile || digest(file.readBytes()) != hash) {
                        val bytes = context.assets.open(face.getString("file")).use { it.readBytes() }
                        check(bytes.take(4).toByteArray().toString(Charsets.US_ASCII) == "OTTO" && digest(bytes) == hash) {
                            "Invalid bundled font"
                        }
                        val target = AtomicFile(file)
                        val output = target.startWrite()
                        try { output.write(bytes); target.finishWrite(output) }
                        catch (error: Exception) { target.failWrite(output); throw error }
                    }
                    Face(file, face.getInt("weight"), requireNotNull(Url("__koofy_fonts/$hash.otf")))
                })
        }
        families = bundled + downloaded(context, downloadedDirectory)
    }

    val optionIds: List<String> get() = listOf("default") + families.map { it.id }
    val optionLabels: List<String> get() = listOf("기본") + families.map { it.label }

    private fun downloaded(context: Context, overrideDirectory: File?): List<Family> {
        val directory = overrideDirectory ?: File(context.filesDir, "cloud_reader/fonts")
        val manifest = File(directory, "catalog.json")
        if (!manifest.isFile || manifest.length() > 1_048_576) return emptyList()
        return runCatching {
            val catalog = JSONObject(manifest.readText())
            check(catalog.getInt("version") == 1)
            val entries = catalog.getJSONArray("families")
            (0 until entries.length()).mapNotNull { index -> runCatching {
                val item = entries.getJSONObject(index)
                val id = item.getString("id")
                check(id.matches(Regex("remote_[a-f0-9]{32}")))
                val label = item.getString("label")
                check(label.isNotBlank() && label.length <= 160)
                val faces = item.getJSONArray("faces")
                check(faces.length() in 1..9)
                Family(id, label, "KoofyRemote_${id.removePrefix("remote_")}",
                    (0 until faces.length()).map { faceIndex ->
                        val face = faces.getJSONObject(faceIndex)
                        val hash = face.getString("sha256")
                        val name = face.getString("file")
                        val weight = face.getInt("weight")
                        check(hash.matches(Regex("[a-f0-9]{64}")) && name in listOf("$hash.otf", "$hash.ttf"))
                        check(weight in 100..900 && weight % 100 == 0)
                        val file = File(directory, name)
                        check(file.canonicalFile.parentFile == directory.canonicalFile && file.length() in 12..10_485_760)
                        val bytes = file.readBytes()
                        val header = bytes.take(4).toByteArray()
                        check(digest(bytes) == hash && (header.contentEquals(byteArrayOf(0, 1, 0, 0)) || header.toString(Charsets.US_ASCII) == "OTTO"))
                        Face(file, weight, requireNotNull(Url("__koofy_fonts/$name")))
                    })
            }.getOrNull() }.distinctBy { it.id }
        }.getOrDefault(emptyList())
    }

    fun family(id: String?): FontFamily? = families.firstOrNull { it.id == id }?.let { FontFamily(it.cssFamily) }

    suspend fun waitUntilStable(reader: EpubNavigatorFragment) = withTimeout(8_000) {
        var previous: String? = null
        var stable = 0
        while (true) {
            val signature = reader.evaluateJavascript("""(function(){
                if(document.readyState!=='complete'||document.fonts.status!=='loaded') return null;
                var r=document.documentElement;
                return [innerWidth,innerHeight,scrollX,scrollY,r.scrollWidth,r.scrollHeight].join(':');
            })()""")
            if (signature != null && signature != "null") {
                stable = if (signature == previous) stable + 1 else 0
                if (stable >= 3) return@withTimeout
            } else stable = 0
            previous = signature
            delay(40)
        }
    }

    fun configure(configuration: EpubNavigatorFragment.Configuration) {
        families.forEach { family ->
            configuration.addFontFamilyDeclaration(FontFamily(family.cssFamily), listOf(FontFamily.SANS_SERIF)) {
                family.faces.forEach { face ->
                    addFontFace {
                        // Readium's publication resource server also serves our private
                        // local files. No file:// permission or remote font host is opened.
                        addSource(requireNotNull(Url("https://readium/publication/${face.href}")))
                        setFontStyle(FontStyle.NORMAL)
                        setFontWeight(FontWeight.values().first { it.value == face.weight })
                    }
                }
            }
        }
    }

    fun container(): Container<Resource> = object : Container<Resource> {
        private val files = families.flatMap { it.faces }.associate { it.href to it.file }
        override val entries: Set<Url> = files.keys
        override fun get(url: Url): Resource? = files[url.removeQuery().removeFragment()]?.let { FileResource(it) }
        override fun close() {}
    }

    companion object {
        val ids = listOf("default", "maplestory", "hakgyoansim-siganpyo")
        fun isValidId(id: String?) = (id ?: "default") in ids || id?.matches(Regex("remote_[a-f0-9]{32}")) == true
        val labels = listOf("기본", "메이플스토리", "학교안심 시간표")
        private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
    }
}
