package com.koofy.reader.bridge

import org.readium.r2.shared.publication.Locator

/** Content positions estimate progress internally; never expose them as page numbers. */
internal class ReaderLocationInfo(all: List<Locator> = emptyList()) {
    private val positions = all.filterNot(::isReaderDisplayCover)
    fun index(locator: Locator): Int? {
        if (positions.isEmpty() || isReaderDisplayCover(locator)) return null
        locator.locations.position?.let { position ->
            positions.indexOfFirst { it.locations.position == position && it.href.removeFragment() == locator.href.removeFragment() }.takeIf { it >= 0 }?.let { return it + 1 }
        }
        val resource = locator.href.removeFragment()
        val candidates = positions.withIndex().filter { it.value.href.removeFragment() == resource }
        if (candidates.isNotEmpty()) {
            val progression = locator.locations.progression ?: 0.0
            return (candidates.lastOrNull { (it.value.locations.progression ?: 0.0) <= progression } ?: candidates.first()).index + 1
        }
        return null
    }
    fun progress(locator: Locator, approximate: Boolean = false): String? {
        val value = locator.locations.totalProgression?.takeIf { it.isFinite() }
            ?: index(locator)?.let { index -> positions[index - 1].locations.totalProgression ?: (index - 1).toDouble() / positions.size }
            ?: return null
        val label = "${(value.coerceIn(0.0, 1.0) * 100).toInt()}%"
        return if (approximate || locator.locations.totalProgression?.isFinite() != true) L("약 {0}", label) else label
    }
    // Legacy location/both settings remain readable, but only progress is shown.
    fun detail(locator: Locator, approximate: Boolean = false): String = progress(locator, approximate).orEmpty()
    fun footer(locator: Locator, mode: String?): String = if (mode == "none") "" else progress(locator).orEmpty()
}
