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
    private val jump: (Locator) -> Unit) {
    fun show() {
        AlertDialog.Builder(context).setTitle("찾기 · 책갈피")
            .setItems(arrayOf("본문 검색", "현재 위치에 책갈피 추가", "책갈피 목록")) { _, i ->
                when (i) { 0 -> search(); 1 -> add(); 2 -> list() }
            }.setNegativeButton("닫기", null).show().also(::tint)
    }
    private fun tint(dialog: AlertDialog) {
        dialog.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(palette.background))
        fun apply(view: android.view.View) {
            if (view is TextView) { view.setTextColor(palette.foreground); view.setHintTextColor(palette.secondary) }
            if (view is android.view.ViewGroup) for (i in 0 until view.childCount) apply(view.getChildAt(i))
        }
        dialog.window?.decorView?.let(::apply)
    }
    private fun message(text: String) = Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    private fun add() {
        val locator = current() ?: return
        val rows = JSONArray(bookmarks())
        if ((0 until rows.length()).any { rows.getJSONObject(it).getJSONObject("locator").toString() == locator.toJSON().toString() }) {
            message("이미 저장한 위치입니다."); return
        }
        if (rows.length() >= 100) { message("책갈피는 책마다 100개까지 저장할 수 있습니다."); return }
        val label = EditText(context).apply { setSingleLine(); setText(snippet(locator).take(120)) }
        val dialog = AlertDialog.Builder(context).setTitle("책갈피 이름").setView(label)
            .setPositiveButton("저장", null).setNegativeButton("취소", null).create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val name = label.text.toString().trim().take(300).ifEmpty { "책갈피" }
                val next = JSONArray(bookmarks())
                if (next.length() >= 100) { message("책갈피가 가득 찼습니다."); return@setOnClickListener }
                next.put(JSONObject().put("id", java.util.UUID.randomUUID().toString()).put("label", name).put("locator", locator.toJSON()))
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
                save(next.toString()) { ok ->
                    if (ok) { dialog.dismiss(); message("책갈피를 저장했습니다.") }
                    else { dialog.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = true; message("저장하지 못했습니다. 다시 시도해 주세요.") }
                }
            }
        }
        dialog.show()
        tint(dialog)
    }
    private fun list() {
        val rows = JSONArray(bookmarks())
        if (rows.length() == 0) { message("저장한 책갈피가 없습니다."); return }
        AlertDialog.Builder(context).setTitle("책갈피")
            .setItems(Array(rows.length()) { rows.getJSONObject(it).getString("label") }) { _, i ->
                val row = rows.getJSONObject(i)
                AlertDialog.Builder(context).setTitle(row.getString("label"))
                    .setPositiveButton("이동") { _, _ -> Locator.fromJSON(row.getJSONObject("locator"))?.let(jump) }
                    .setNeutralButton("삭제") { _, _ ->
                        val all = JSONArray(bookmarks()); val next = JSONArray()
                        for (n in 0 until all.length()) if (all.getJSONObject(n).getString("id") != row.getString("id")) next.put(all.getJSONObject(n))
                        save(next.toString()) { ok -> message(if (ok) "책갈피를 삭제했습니다." else "삭제하지 못했습니다.") }
                    }.setNegativeButton("취소", null).show().also(::tint)
            }.setNegativeButton("닫기", null).show().also(::tint)
    }
    private fun search() {
        val query = EditText(context).apply { hint = "단어 또는 문장 검색"; setSingleLine(); maxEms = 100 }
        val submit = Button(context).apply { text = "검색" }
        val more = Button(context).apply { text = "더 보기"; isEnabled = false }
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
        val dialog = AlertDialog.Builder(context).setTitle("본문 검색").setView(panel).setNegativeButton("닫기", null).create()
        var iterator: SearchIterator? = null
        var job: Job? = null
        var serial = 0
        fun load(reset: Boolean) {
            val term = query.text.toString().trim()
            if (term.isEmpty() || term.length > 200) { status.text = "검색어를 1~200자로 입력해 주세요."; return }
            val run = ++serial
            job?.cancel()
            if (reset) { iterator?.close(); iterator = null; results.clear(); labels.clear(); adapter.notifyDataSetChanged() }
            more.isEnabled = false; status.text = "검색 중…"
            job = scope.launch {
                try {
                    val active = iterator ?: publication.search(term)?.also { iterator = it }
                        ?: throw IllegalStateException("이 책은 본문 검색을 지원하지 않습니다.")
                    val page = withContext(Dispatchers.Default) { active.next().getOrElse { throw IllegalStateException(it.message) } }
                    if (run != serial || !dialog.isShowing) return@launch
                    val found = page?.locators.orEmpty().take(500 - results.size)
                    results.addAll(found); labels.addAll(found.map(::snippet)); adapter.notifyDataSetChanged()
                    more.isEnabled = page != null && results.size < 500
                    status.text = when {
                        results.size >= 500 -> "500개까지 표시합니다. 검색어를 더 구체적으로 입력해 주세요."
                        page == null && results.isEmpty() -> "검색 결과가 없습니다."
                        else -> "${results.size}개 찾음" + if (page != null) " · 더 보기로 계속 검색" else ""
                    }
                } catch (_: CancellationException) { }
                catch (e: Exception) { if (run == serial) status.text = "검색하지 못했습니다. 다시 검색해 주세요." }
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
        return excerpt.ifEmpty { json.optString("title").ifEmpty { "저장한 본문 위치" } }
    }
}
