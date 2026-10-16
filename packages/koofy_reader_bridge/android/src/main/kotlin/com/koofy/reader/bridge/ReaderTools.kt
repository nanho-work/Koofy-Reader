@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
package com.koofy.reader.bridge

import android.content.Context
import android.widget.*
import androidx.appcompat.app.AlertDialog
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.search.search
import org.readium.r2.shared.publication.services.search.SearchIterator
import org.readium.r2.shared.util.getOrElse

/** Search reads local publication resources and only keeps a bounded result page. */
internal class ReaderTools(private val context: Context, private val scope: CoroutineScope,
    private val publication: Publication, private val palette: ReaderPalette, private val current: () -> Locator?,
    private val bookmarks: () -> String, private val save: (String, (Boolean) -> Unit) -> Unit,
    private val jump: (Locator) -> Unit, private val detail: (Locator) -> String = { "" }) {
    private var bookmarkDialog: AlertDialog? = null
    private var saving = false
    private fun entries() = JSONArray(bookmarks()).let { rows -> (0 until rows.length()).map { rows.getJSONObject(it) } }
    private fun encoded(rows: List<JSONObject>) = JSONArray().apply { rows.forEach { put(it) } }.toString()
    private fun matching(rows: List<JSONObject>, locator: Locator?) = locator?.let { target ->
        rows.firstOrNull { row -> ReaderBookmarkIdentity.decode(row.getJSONObject("locator"))?.let { ReaderBookmarkIdentity.same(it, target) } == true }
    }
    private fun commit(rows: List<JSONObject>, done: (Boolean) -> Unit) {
        if (saving) return
        saving = true
        save(encoded(rows)) { ok -> scope.launch(Dispatchers.Main.immediate) {
            saving = false; done(ok)
        } }
    }
    fun show() {
        if (bookmarkDialog?.isShowing == true) return
        val anchor = current()
        var undo: Pair<JSONObject, Int>? = null
        var rows = entries().reversed()
        fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
        fun action(title: String, destructive: Boolean = false, block: () -> Unit) = Button(context).apply {
            text = title; isAllCaps = false; textSize = 14f; minimumHeight = dp(48); minWidth = 0; minimumWidth = 0
            setPadding(dp(8), dp(8), dp(8), dp(8))
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            setTextColor(if (destructive) if (palette.background == ReaderPalette.forTheme("dark").background) 0xFFFFB4AB.toInt() else 0xFFB3261E.toInt() else palette.accent)
            setOnClickListener { if (!saving) block() }
        }
        fun text(value: String, secondary: Boolean = false) = TextView(context).apply {
            this.text = value; textSize = if (secondary) 12f else 16f
            setTextColor(if (secondary) palette.secondary else palette.foreground)
            setPadding(0, dp(4), 0, dp(4)); maxLines = if (secondary) 2 else 3
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        val panel = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(palette.background); setPadding(dp(16), dp(8), dp(16), dp(8)) }
        val title = text(L("책갈피"))
        val header = LinearLayout(context).apply { gravity = android.view.Gravity.CENTER_VERTICAL; isBaselineAligned = false }
        header.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
        val dialog = AlertDialog.Builder(context).create(); bookmarkDialog = dialog
        header.addView(action(L("닫기")) { dialog.dismiss() })
        panel.addView(header)
        val toggle = action("") {}; toggle.tag = "bookmark-toggle"
        panel.addView(toggle)
        val undoButton = action(L("삭제 실행 취소")) {}; undoButton.tag = "bookmark-undo"; panel.addView(undoButton)
        val empty = text(L("저장한 책갈피가 없습니다."), true).apply { gravity = android.view.Gravity.CENTER; visibility = android.view.View.GONE }
        panel.addView(empty, LinearLayout.LayoutParams(-1, 0, 1f))
        val list = ListView(context).apply { tag = "bookmark-list"; dividerHeight = dp(1); divider = android.graphics.drawable.ColorDrawable(palette.secondary and 0x00ffffff or 0x22000000) }
        panel.addView(list, LinearLayout.LayoutParams(-1, 0, 1f)); list.emptyView = empty
        lateinit var refresh: () -> Unit
        fun remove(id: String) {
            val all = entries(); val index = all.indexOfFirst { it.getString("id") == id }
            if (index < 0) { refresh(); return }
            val deleted = JSONObject(all[index].toString())
            commit(all.filterNot { it.getString("id") == id }) { ok ->
                if (ok) undo = deleted to index else message(L("삭제하지 못했습니다."))
                refresh()
            }
        }
        fun rename(id: String) {
            val row = entries().firstOrNull { it.getString("id") == id } ?: return
            val field = EditText(context).apply { setSingleLine(); setText(row.getString("label")); selectAll() }
            val editor = AlertDialog.Builder(context).setTitle(L("책갈피 이름")).setView(field).setPositiveButton(L("저장"), null).setNegativeButton(L("취소"), null).create()
            editor.show(); tint(editor)
            editor.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                if (saving) return@setOnClickListener
                val all = entries()
                all.firstOrNull { it.getString("id") == id }?.put("label", ReaderBookmarkIdentity.label(field.text.toString()))
                commit(all) { ok -> if (ok) editor.dismiss() else message(L("저장하지 못했습니다. 다시 시도해 주세요.")); refresh() }
            }
        }
        val adapter = object : BaseAdapter() {
            override fun getCount() = rows.size
            override fun getItem(position: Int) = rows[position]
            override fun getItemId(position: Int) = position.toLong()
            override fun getView(position: Int, convertView: android.view.View?, parent: android.view.ViewGroup): android.view.View {
                val row = rows[position]; val id = row.getString("id")
                val locator = ReaderBookmarkIdentity.decode(row.getJSONObject("locator"))
                val item = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; setPadding(0, dp(8), 0, dp(8)); setBackgroundColor(palette.background) }
                item.addView(text(row.getString("label")))
                if (locator != null) {
                    val excerpt = snippet(locator)
                    if (excerpt != row.getString("label")) item.addView(text(excerpt, true))
                    val metadata = detail(locator)
                    if (metadata.isNotBlank()) item.addView(text(metadata, true))
                    item.setOnClickListener { if (!saving) { dialog.dismiss(); jump(locator) } }
                }
                val controls = LinearLayout(context).apply { isBaselineAligned = false }
                controls.addView(action(L("이동")) { if (locator != null) { dialog.dismiss(); jump(locator) } }.apply { tag = "bookmark-open-$id"; isEnabled = locator != null }, LinearLayout.LayoutParams(0, -2, 1f))
                controls.addView(action(L("이름 변경")) { rename(id) }.apply { tag = "bookmark-rename-$id" }, LinearLayout.LayoutParams(0, -2, 1f))
                controls.addView(action(L("삭제"), true) { remove(id) }.apply { tag = "bookmark-delete-$id"; contentDescription = L("{0} 책갈피 삭제", row.getString("label")) }, LinearLayout.LayoutParams(0, -2, 1f))
                item.addView(controls); return item
            }
        }
        list.adapter = adapter
        refresh = {
            rows = entries().reversed()
            title.text = L("책갈피 {0}개", rows.size)
            val saved = matching(rows, anchor)
            toggle.text = if (saved == null) L("이곳에 책갈피 추가") else L("이곳의 책갈피 해제")
            toggle.isEnabled = anchor != null && !isReaderDisplayCover(anchor) && !saving
            toggle.setOnClickListener {
                if (!saving && anchor != null) {
                    val existing = matching(entries(), anchor)
                    if (existing != null) remove(existing.getString("id"))
                    else {
                        val all = entries()
                        if (all.size >= 100) message(L("책갈피는 책마다 100개까지 저장할 수 있습니다."))
                        else commit(all + JSONObject().put("id", java.util.UUID.randomUUID().toString()).put("label", ReaderBookmarkIdentity.label(snippet(anchor))).put("locator", anchor.toJSON())) { ok ->
                            if (!ok) message(L("저장하지 못했습니다. 다시 시도해 주세요."))
                            else undo?.first?.optJSONObject("locator")?.let { ReaderBookmarkIdentity.decode(it) }?.let { if (ReaderBookmarkIdentity.same(it, anchor)) undo = null }
                            refresh()
                        }
                    }
                }
            }
            undoButton.visibility = if (undo != null) android.view.View.VISIBLE else android.view.View.GONE
            undoButton.setOnClickListener {
                if (!saving) undo?.let { (row, index) ->
                    val all = entries().toMutableList()
                    if (all.size >= 100) message(L("책갈피는 책마다 100개까지 저장할 수 있습니다."))
                    else if (all.none { it.getString("id") == row.getString("id") }) {
                        all.add(index.coerceIn(0, all.size), row)
                        commit(all) { ok -> if (ok) undo = null else message(L("저장하지 못했습니다. 다시 시도해 주세요.")); refresh() }
                    }
                }
            }
            adapter.notifyDataSetChanged()
        }
        refresh()
        dialog.show(); dialog.setContentView(panel, android.view.ViewGroup.LayoutParams(-1, -1))
        dialog.window?.apply {
            setBackgroundDrawable(android.graphics.drawable.ColorDrawable(palette.background))
            setLayout(minOf(context.resources.displayMetrics.widthPixels - dp(24), dp(480)), (context.resources.displayMetrics.heightPixels * .82).toInt())
        }
    }
    private fun tint(dialog: AlertDialog) {
        dialog.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(palette.background))
        dialog.listView?.setBackgroundColor(palette.background)
        fun apply(view: android.view.View) {
            if (view is TextView) { view.setTextColor(palette.foreground); view.setHintTextColor(palette.secondary) }
            if (view is android.view.ViewGroup) for (i in 0 until view.childCount) apply(view.getChildAt(i))
        }
        dialog.window?.decorView?.let(::apply)
    }
    private fun message(text: String) = Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    fun add(selectedOnly: Boolean = false) {
        if (saving) return
        val locator = current() ?: return
        if (isReaderDisplayCover(locator)) { message(L("책갈피는 본문에서 추가해 주세요.")); return }
        val rows = entries()
        if (matching(rows, locator) != null) { show(); return }
        if (rows.size >= 100) { message(L("책갈피는 책마다 100개까지 저장할 수 있습니다.")); return }
        val name = if (selectedOnly) locator.text.highlight?.takeIf { it.isNotBlank() } ?: snippet(locator) else snippet(locator)
        val row = JSONObject().put("id", java.util.UUID.randomUUID().toString()).put("label", ReaderBookmarkIdentity.label(name)).put("locator", locator.toJSON())
        commit(rows + row) { ok -> if (ok) { message(L("책갈피를 저장했습니다.")); show() } else message(L("저장하지 못했습니다. 다시 시도해 주세요.")) }
    }
    fun search() {
        val query = EditText(context).apply { hint = L("단어 또는 문장 검색"); setSingleLine(); maxEms = 100 }
        val submit = Button(context).apply { text = L("검색") }
        val more = Button(context).apply { text = L("더 보기"); isEnabled = false }
        val status = TextView(context)
        val results = mutableListOf<Locator>()
        val labels = mutableListOf<String>()
        val adapter = object : ArrayAdapter<String>(context, android.R.layout.simple_list_item_1, labels) {
            override fun getView(position: Int, convertView: android.view.View?, parent: android.view.ViewGroup): android.view.View =
                super.getView(position, convertView, parent).also { (it as? TextView)?.setTextColor(palette.foreground) }
        }
        val list = ListView(context).apply { this.adapter = adapter }
        val panel = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL; setPadding(24, 8, 24, 8)
            addView(query); addView(submit); addView(status)
            addView(list, LinearLayout.LayoutParams(-1, 0, 1f)); addView(more)
        }
        val dialog = AlertDialog.Builder(context).setTitle(L("본문 검색")).setView(panel).setNegativeButton(L("닫기"), null).create()
        var iterator: SearchIterator? = null
        var job: Job? = null
        var serial = 0
        fun load(reset: Boolean) {
            val term = query.text.toString().trim()
            if (term.isEmpty() || term.length > 200) { status.text = L("검색어를 1~200자로 입력해 주세요."); return }
            val run = ++serial
            job?.cancel()
            if (reset) { iterator?.close(); iterator = null; results.clear(); labels.clear(); adapter.notifyDataSetChanged() }
            more.isEnabled = false; status.text = L("검색 중…")
            job = scope.launch {
                try {
                    val active = iterator ?: publication.search(term)?.also { iterator = it }
                        ?: throw IllegalStateException(L("이 책은 본문 검색을 지원하지 않습니다."))
                    val page = withContext(Dispatchers.Default) { active.next().getOrElse { throw IllegalStateException(it.message) } }
                    if (run != serial || !dialog.isShowing) return@launch
                    val found = page?.locators.orEmpty().take(500 - results.size)
                    results.addAll(found); labels.addAll(found.map(::snippet)); adapter.notifyDataSetChanged()
                    more.isEnabled = page != null && results.size < 500
                    status.text = when {
                        results.size >= 500 -> L("500개까지 표시합니다. 검색어를 더 구체적으로 입력해 주세요.")
                        page == null && results.isEmpty() -> L("검색 결과가 없습니다.")
                        else -> L("{0}개 찾음", results.size) + if (page != null) L(" · 더 보기로 계속 검색") else ""
                    }
                } catch (_: CancellationException) { }
                catch (e: Exception) { if (run == serial) status.text = L("검색하지 못했습니다. 다시 검색해 주세요.") }
            }
        }
        submit.setOnClickListener { load(true) }; more.setOnClickListener { load(false) }
        query.setOnEditorActionListener { _, _, _ -> load(true); true }
        list.setOnItemClickListener { _, _, i, _ -> val target = results[i]; dialog.dismiss(); jump(target) }
        dialog.setOnDismissListener { serial++; job?.cancel(); iterator?.close(); iterator = null }
        dialog.show()
        tint(dialog)
        dialog.window?.setLayout(-1, (context.resources.displayMetrics.heightPixels * .8).toInt())
    }
    private fun snippet(locator: Locator): String {
        val json = locator.toJSON(); val text = json.optJSONObject("text")
        val excerpt = listOf(text?.optString("before"), text?.optString("highlight"), text?.optString("after"))
            .filterNotNull().joinToString("").replace(Regex("\\s+"), " ").trim().take(180)
        return excerpt.ifEmpty { json.optString("title").ifEmpty { L("저장한 본문 위치") } }
    }
}
