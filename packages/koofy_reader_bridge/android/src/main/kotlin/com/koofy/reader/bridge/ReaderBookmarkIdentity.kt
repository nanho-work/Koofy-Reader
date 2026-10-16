package com.koofy.reader.bridge

import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator

/** Compare exact anchors, never a rounded percentage or position number. */
internal object ReaderBookmarkIdentity {
    // Readium consumes some JSON fields while decoding. Never pass a stored row.
    fun decode(json: JSONObject): Locator? = Locator.fromJSON(JSONObject(json.toString()))
    fun same(a: Locator, b: Locator): Boolean {
        if (a.href.removeFragment() != b.href.removeFragment()) return false
        val left = a.toJSON(); val right = b.toJSON()
        val x = left.optJSONObject("locations")?.optJSONObject("koofyText")
        val y = right.optJSONObject("locations")?.optJSONObject("koofyText")
        if (x != null || y != null) return x != null && y != null && canonical(x) == canonical(y)
        return canonical(left) == canonical(right)
    }
    private fun canonical(value: Any?): String = when (value) {
        is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(prefix = "{", postfix = "}") { JSONObject.quote(it) + ":" + canonical(value.get(it)) }
        is JSONArray -> (0 until value.length()).joinToString(prefix = "[", postfix = "]") { canonical(value.get(it)) }
        is String -> JSONObject.quote(value)
        is Number -> java.math.BigDecimal(value.toString()).stripTrailingZeros().toPlainString()
        else -> value.toString()
    }
    fun label(text: String): String {
        val limited = text.trim().take(300)
        return (if (limited.lastOrNull()?.isHighSurrogate() == true) limited.dropLast(1) else limited).ifEmpty { L("책갈피") }
    }
}
