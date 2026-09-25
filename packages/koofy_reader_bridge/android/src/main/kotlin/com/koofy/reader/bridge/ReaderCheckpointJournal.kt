package com.koofy.reader.bridge

import android.util.AtomicFile
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject

/** Latest durable snapshot per session, kept independently from Flutter's domain database. */
internal class ReaderCheckpointJournal(filesDir: File) {
    private val directory = File(filesDir, "koofy-reader-checkpoints-v1")

    private fun file(sessionId: String): AtomicFile {
        check(directory.exists() || directory.mkdirs()) { "Cannot create reader recovery directory" }
        val key = MessageDigest.getInstance("SHA-256").digest(sessionId.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return AtomicFile(File(directory, "$key.json"))
    }

    @Synchronized fun write(event: ReaderEvent) {
        require(event.kind in setOf("ready", "locationChanged", "preferencesChanged", "closed")) {
            "Only reader state snapshots belong in the recovery journal"
        }
        val target = file(event.sessionId)
        // Independent identity lets a damaged snapshot block only its own book.
        val identity = AtomicFile(File(target.baseFile.path + ".identity"))
        val identityOutput = identity.startWrite()
        try {
            identityOutput.write(JSONObject().put("publicationId", event.publicationId)
                .toString().toByteArray(Charsets.UTF_8))
            identity.finishWrite(identityOutput)
        } catch (error: Exception) {
            identity.failWrite(identityOutput)
            throw error
        }
        val output = target.startWrite()
        try {
            output.write(encode(event).toString().toByteArray(Charsets.UTF_8))
            target.finishWrite(output)
        } catch (error: Exception) {
            target.failWrite(output)
            throw error
        }
    }

    @Synchronized fun pending(): List<ReaderEvent> {
        if (!directory.exists()) return emptyList()
        return directory.listFiles().orEmpty()
            .filter { it.name.endsWith(".json") || it.name.endsWith(".json.bak") }
            .map { it.path.removeSuffix(".bak") }.distinct()
            .map { path ->
                try {
                    decode(JSONObject(String(AtomicFile(File(path)).readFully(), Charsets.UTF_8)))
                } catch (_: Exception) {
                    val publication = sequenceOf(path + ".identity", path).mapNotNull { candidate ->
                        runCatching { JSONObject(String(AtomicFile(File(candidate)).readFully(), Charsets.UTF_8))
                            .optString("publicationId").takeIf { it.isNotBlank() } }.getOrNull()
                    }.firstOrNull() ?: ""
                    ReaderEvent(protocolVersion = 1, sessionId = File(path).name,
                        sessionGeneration = 0, publicationId = publication, contentRevision = "",
                        sequence = 0, kind = "recoveryIssue", errorCode = "checkpoint_corrupt",
                        message = "읽기 복구 기록이 손상되었습니다. 원본 기록은 보존되어 있습니다.")
                }
            }
            .sortedWith(compareBy({ it.sessionGeneration }, { it.sequence }))
    }

    @Synchronized fun acknowledge(sessionId: String, sequence: Long) {
        val target = file(sessionId)
        if (!target.baseFile.exists() && !File(target.baseFile.path + ".bak").exists()) return
        val event = decode(JSONObject(String(target.readFully(), Charsets.UTF_8)))
        if (event.sessionId == sessionId && event.sequence == sequence) {
            target.delete()
            AtomicFile(File(target.baseFile.path + ".identity")).delete()
        }
    }

    private fun encode(event: ReaderEvent) = JSONObject().apply {
        put("schema", 1)
        put("protocolVersion", event.protocolVersion)
        put("sessionId", event.sessionId)
        put("sessionGeneration", event.sessionGeneration)
        put("publicationId", event.publicationId)
        put("contentRevision", event.contentRevision)
        put("sequence", event.sequence)
        put("kind", event.kind)
        put("locatorJson", event.locatorJson)
        put("bookmarksJson", event.bookmarksJson)
        put("errorCode", event.errorCode)
        put("message", event.message)
        event.preferences?.let { preferences ->
            put("preferences", JSONObject().apply {
                put("fontScale", preferences.fontScale)
                put("columnCount", preferences.columnCount)
                put("scroll", preferences.scroll)
                put("theme", preferences.theme)
                put("pageTurnStyle", preferences.pageTurnStyle ?: "instant")
                put("fontId", preferences.fontId ?: "default")
                put("lineHeight", preferences.lineHeight)
                put("paragraphSpacing", preferences.paragraphSpacing)
                put("pageMargins", preferences.pageMargins)
            })
        }
    }

    private fun decode(json: JSONObject): ReaderEvent {
        require(json.getInt("schema") == 1) { "Unsupported recovery record" }
        return ReaderEvent(
            protocolVersion = json.getLong("protocolVersion"),
            sessionId = json.getString("sessionId"),
            sessionGeneration = json.getLong("sessionGeneration"),
            publicationId = json.getString("publicationId"),
            contentRevision = json.getString("contentRevision"),
            sequence = json.getLong("sequence"),
            kind = json.getString("kind"),
            locatorJson = json.optionalString("locatorJson"),
            bookmarksJson = json.optionalString("bookmarksJson"),
            preferences = json.optJSONObject("preferences")?.let {
                ReaderPreferences(it.getDouble("fontScale"), it.getLong("columnCount"),
                    it.getBoolean("scroll"), it.getString("theme"), it.optionalString("pageTurnStyle"), it.optionalString("fontId"),
                    it.optionalDouble("lineHeight"), it.optionalDouble("paragraphSpacing"), it.optionalDouble("pageMargins"))
            },
            errorCode = json.optionalString("errorCode"),
            message = json.optionalString("message"),
        )
    }

    private fun JSONObject.optionalDouble(key: String): Double? =
        if (has(key) && !isNull(key)) getDouble(key) else null

    private fun JSONObject.optionalString(key: String): String? =
        if (has(key) && !isNull(key)) getString(key) else null
}
