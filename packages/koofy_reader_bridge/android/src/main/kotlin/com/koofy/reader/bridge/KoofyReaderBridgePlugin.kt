package com.koofy.reader.bridge

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.io.File
import java.util.concurrent.Executors

/** The Flutter engine is retained behind a separate native reader Activity. */
class KoofyReaderBridgePlugin : FlutterPlugin, ActivityAware, ReaderHostApi {
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ReaderRuntime.initialize(binding.applicationContext)
        ReaderRuntime.events = ReaderFlutterApi(binding.binaryMessenger)
        ReaderHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ReaderHostApi.setUp(binding.binaryMessenger, null)
        ReaderRuntime.events = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onDetachedFromActivity() { activity = null }

    override fun openReader(request: ReaderLaunchRequest, callback: (Result<Unit>) -> Unit) {
        callback(runCatching {
            check(request.protocolVersion == 1L) { "Unsupported reader protocol" }
            check(ReaderRuntime.session == null) { "A reader session is already active" }
            val host = checkNotNull(activity) { "The Flutter activity is not attached" }
            require(request.sessionId.isNotBlank() && request.contentRevision.isNotBlank())
            require(request.sessionGeneration > 0)
            validatePreferences(request.preferences)
            val file = File(request.filePath).canonicalFile
            val root = File(host.applicationInfo.dataDir).canonicalFile
            require(file.path.startsWith(root.path + File.separator) && file.isFile && file.canRead()) {
                "The reader requires an app-owned, readable EPUB file"
            }
            val session = ReaderSession(request)
            ReaderRuntime.session = session
            try {
                host.startActivity(Intent(host, ReaderActivity::class.java)
                    .putExtra(ReaderActivity.SESSION_ID, request.sessionId))
            } catch (error: Exception) {
                ReaderRuntime.session = null
                throw error
            }
        })
    }

    override fun updateAdHiddenUntil(epochMs: Long?, callback: (Result<Unit>) -> Unit) {
        ReaderRuntime.session?.adHiddenUntilEpochMs = epochMs
        ReaderRuntime.reader?.updateAdHiddenUntil(epochMs)
        callback(Result.success(Unit))
    }

    override fun closeReader(sessionId: String, callback: (Result<Unit>) -> Unit) {
        callback(runCatching {
            val current = checkNotNull(ReaderRuntime.session) { "No active reader session" }
            check(current.request.sessionId == sessionId) { "Stale reader session" }
            current.closeRequested = true
            ReaderRuntime.reader?.closeReader()
            // startActivity() is asynchronous. ReaderActivity honors this flag before
            // starting publication parsing if Flutter cancels during launch.
            Unit
        })
    }

    override fun goTo(sessionId: String, locatorJson: String, callback: (Result<Unit>) -> Unit) {
        callback(runCatching { requireActivity(sessionId).goToLocator(locatorJson) })
    }

    override fun applyPreferences(sessionId: String, preferences: ReaderPreferences, callback: (Result<Unit>) -> Unit) {
        callback(runCatching {
            validatePreferences(preferences)
            requireActivity(sessionId).applyReaderPreferences(preferences)
        })
    }

    override fun pendingCheckpoints(callback: (Result<List<ReaderEvent>>) -> Unit) {
        ReaderRuntime.io.execute {
            val result = runCatching { ReaderRuntime.journal.pending() }
            ReaderRuntime.main.post { callback(result) }
        }
    }

    override fun acknowledgeCheckpoint(sessionId: String, sequence: Long, callback: (Result<Unit>) -> Unit) {
        ReaderRuntime.io.execute {
            val result = runCatching { ReaderRuntime.journal.acknowledge(sessionId, sequence) }
            ReaderRuntime.main.post { callback(result) }
        }
    }

    private fun requireActivity(id: String): ReaderActivity {
        check(ReaderRuntime.session?.request?.sessionId == id) { "Stale reader session" }
        return checkNotNull(ReaderRuntime.reader) { "The reader is not ready" }
    }
}

internal fun validatePreferences(value: ReaderPreferences) {
    require(value.fontScale.isFinite() && value.fontScale in 0.5..3.0) { "Invalid font scale" }
    require(value.columnCount in 0L..2L) { "Invalid column count" }
    require(value.theme in listOf("light", "sepia", "dark")) { "Invalid reader theme" }
    require(ReaderFonts.isValidId(value.fontId)) { "Invalid reader font" }
    require(value.pageTurnStyle == null || value.pageTurnStyle in listOf("instant", "curl")) { "Invalid page turn style" }
}

internal class ReaderSession(val request: ReaderLaunchRequest) {
    var adHiddenUntilEpochMs = request.adHiddenUntilEpochMs
    var sequence = 0L
    var preferences = request.preferences
    var locatorJson = request.initialLocatorJson
    var ready = false
    var closing = false
    var closeRequested = false

    fun event(kind: String, errorCode: String? = null, message: String? = null) = ReaderEvent(
        protocolVersion = request.protocolVersion,
        sessionId = request.sessionId,
        sessionGeneration = request.sessionGeneration,
        publicationId = request.publicationId,
        contentRevision = request.contentRevision,
        sequence = ++sequence,
        kind = kind,
        locatorJson = locatorJson,
        preferences = preferences,
        errorCode = errorCode,
        message = message,
    )
}

internal object ReaderRuntime {
    val main = Handler(Looper.getMainLooper())
    val io = Executors.newSingleThreadExecutor()
    lateinit var journal: ReaderCheckpointJournal
    var events: ReaderFlutterApi? = null
    var session: ReaderSession? = null
    var reader: ReaderActivity? = null

    fun initialize(context: Context) {
        if (!::journal.isInitialized) journal = ReaderCheckpointJournal(context.filesDir)
    }

    /** Persist before delivery; Flutter acknowledgements cannot delete a newer checkpoint. */
    fun emit(event: ReaderEvent, completion: (Result<Unit>) -> Unit = {}) {
        // Diagnostics are not state snapshots. Replacing the last good locator with an
        // error would poison recovery if the process dies while the alert is visible.
        if (event.kind == "error") {
            events?.onEvent(event) { }
            completion(Result.success(Unit))
            return
        }
        io.execute {
            val result = runCatching { journal.write(event) }
            main.post {
                if (result.isSuccess) {
                    events?.onEvent(event) { /* DB acknowledgement is a separate host call. */ }
                }
                completion(result)
            }
        }
    }
}
