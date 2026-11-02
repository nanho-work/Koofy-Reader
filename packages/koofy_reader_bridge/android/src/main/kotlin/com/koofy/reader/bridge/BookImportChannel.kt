package com.koofy.reader.bridge

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Select handles first. Cloud bytes are copied on demand, off the UI thread. */
internal class BookImportChannel(private val context: Context, messenger: BinaryMessenger) : PluginRegistry.ActivityResultListener {
    private val channel = MethodChannel(messenger, "koofy_reader/book_import")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null
    @Volatile private var cancelled = false
    @Volatile private var copying = false
    private val allowed = setOf("txt", "epub", "png", "jpg", "jpeg", "webp")
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    val activity = binding?.activity
                    if (activity == null || pending != null || copying) {
                        result.error("busy", "File selection is unavailable", null)
                    } else {
                        pending = result
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "application/epub+zip", "image/jpeg", "image/png", "image/webp"))
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }, 7412)
                        } catch (error: Exception) {
                            pending = null; result.error("picker", error.message, null)
                        }
                    }
                }
                "copy" -> {
                    if (copying) { result.error("busy", "Previous file request is still stopping", null); return@setMethodCallHandler }
                    val source = call.argument<String>("source")
                    val name = call.argument<String>("name")
                    val limit = call.argument<Number>("limit")?.toLong() ?: 0L
                    if (source == null || name == null || File(name).name != name || name.substringAfterLast('.').lowercase() !in allowed || limit !in 1..(40L * 1024 * 1024) || copying) {
                        result.error("invalid_file", "Invalid selected file", null)
                    } else {
                        copying = true; cancelled = false
                        io.execute {
                            var folder: File? = null
                            try {
                                val uri = Uri.parse(source)
                                require(uri.scheme == "content")
                                folder = File(context.cacheDir, "koofy_import/${UUID.randomUUID()}").apply { mkdirs() }
                                val temporary = File(folder, "download.part")
                                var count = 0L; var reported = 0L
                                context.contentResolver.openInputStream(uri).use { input ->
                                    requireNotNull(input)
                                    temporary.outputStream().use { output ->
                                        val buffer = ByteArray(64 * 1024)
                                        while (true) {
                                            check(!cancelled) { "cancelled" }
                                            val length = input.read(buffer)
                                            if (length < 0) break
                                            count += length
                                            require(count <= limit) { "file_too_large" }
                                            output.write(buffer, 0, length)
                                            if (count - reported >= 256 * 1024) {
                                                reported = count
                                                val received = count
                                                main.post { channel.invokeMethod("progress", mapOf("bytes" to received)) }
                                            }
                                        }
                                    }
                                }
                                check(!cancelled) { "cancelled" }
                                require(count > 0) { "empty_file" }
                                val target = File(folder, name)
                                check(temporary.renameTo(target))
                                main.post { result.success(target.path) }
                            } catch (error: Exception) {
                                folder?.deleteRecursively()
                                main.post { result.error(if (cancelled) "cancelled" else "file_access", error.message, null) }
                            } finally { copying = false }
                        }
                    }
                }
                "cancel" -> { cancelled = true; result.success(null) }
                "release" -> {
                    val source = call.argument<String>("source")
                    try { if (source != null) context.contentResolver.releasePersistableUriPermission(Uri.parse(source), Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    fun attach(value: ActivityPluginBinding) { binding = value; value.addActivityResultListener(this) }
    fun detach() { binding?.removeActivityResultListener(this); binding = null }
    fun dispose() { detach(); cancelled = true; pending?.error("detached", "File picker closed", null); pending = null; channel.setMethodCallHandler(null); io.shutdown() }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 7412) return false
        val result = pending ?: return true
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) { result.success(emptyList<Any>()); return true }
        val uris = data.clipData?.let { clips -> (0 until clips.itemCount).map { clips.getItemAt(it).uri } } ?: listOfNotNull(data.data)
        io.execute {
            try {
                val files = uris.distinct().mapNotNull { uri ->
                    try { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { }
                    val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) cursor.getString(0) else null
                    } ?: uri.lastPathSegment ?: "file"
                    if (name.substringAfterLast('.').lowercase() !in allowed) null else mapOf("name" to File(name).name, "source" to uri.toString())
                }
                main.post { result.success(files) }
            } catch (error: Exception) { main.post { result.error("metadata", error.message, null) } }
        }
        return true
    }
}
