@file:OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
package com.koofy.reader.bridge

import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.content
import org.readium.r2.shared.util.Language
import org.readium.r2.shared.util.tokenizer.DefaultTextContentTokenizer
import org.readium.r2.shared.util.tokenizer.TextUnit

internal data class SpeechStart(val locator: Locator, val skip: Int)

/** Readium's content iterator seeks elements, not a sentence inside them. Keep its full
 * cursor (so Previous still works), silently advancing only the sentences before the anchor. */
internal suspend fun speechStart(publication: Publication, target: Locator): SpeechStart {
    val json = target.toJSON()
    val locations = json.optJSONObject("locations") ?: JSONObject().also { json.put("locations", it) }
    if (!locations.has("cssSelector")) target.locations.fragments.firstOrNull()?.let { id ->
        locations.put("cssSelector", "[id=\"${id.replace("\\", "\\\\").replace("\"", "\\\"")}\"]")
    }
    val locator = requireNotNull(Locator.fromJSON(json))
    val ordinal = locations.optInt("koofySpeechOrdinal", -1)
    if (ordinal >= 0) return SpeechStart(locator, ordinal.coerceAtMost(100_000))
    if (target.text.highlight.isNullOrEmpty()) return SpeechStart(locator, 0)
    val element = publication.content(locator)?.iterator()?.nextOrNull() as? Content.TextElement
        ?: return SpeechStart(locator, 0)
    var skip = 0
    for (segment in element.segments) {
        val ranges = DefaultTextContentTokenizer(TextUnit.Sentence, Language("ko")).tokenize(segment.text)
        val position = speechQuoteOffset(segment.text, target.text.before, target.text.highlight, target.text.after)
        if (position != null) {
            val index = ranges.indexOfFirst { compactSpeech(segment.text.substring(0, it.last + 1)).length > position }
            return SpeechStart(locator, skip + if (index < 0) ranges.lastIndex.coerceAtLeast(0) else index)
        }
        skip += ranges.size
    }
    error("읽던 문장을 찾지 못했습니다. 본문 위치를 옮긴 뒤 다시 재생해 주세요.")
}
internal fun compactSpeech(value: String) = value.filterNot { it.isWhitespace() }
internal fun speechQuoteOffset(text: String, before: String?, highlight: String?, after: String?): Int? {
    val source = compactSpeech(text)
    val head = compactSpeech(before.orEmpty())
    val quote = compactSpeech(highlight.orEmpty())
    val tail = compactSpeech(after.orEmpty())
    if (quote.isEmpty()) return 0
    val context = head + quote + tail
    (if (tail.isEmpty() && head.isNotEmpty()) source.lastIndexOf(context) else source.indexOf(context)).takeIf { it >= 0 }?.let { return it + head.length }
    // Content extraction may trim preceding/following nodes; retain the available side.
    if (head.isNotEmpty()) source.indexOf(head + quote).takeIf { it >= 0 }?.let { return it + head.length }
    if (tail.isNotEmpty()) source.indexOf(quote + tail).takeIf { it >= 0 }?.let { return it }
    if (quote.length > 4) source.indexOf(quote).takeIf { it >= 0 }?.let { return it }
    return null
}
