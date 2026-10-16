package com.koofy.reader.bridge

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.TextView

/** ListView creates/recycles rows after the dialog's initial view traversal. */
internal class ReaderTextListAdapter(context: Context, rows: List<String>, private val palette: ReaderPalette) :
    ArrayAdapter<String>(context, android.R.layout.simple_list_item_1, rows) {
    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
        (super.getView(position, convertView, parent) as TextView).apply {
            setTextColor(palette.foreground)
            isSingleLine = false
            maxLines = Int.MAX_VALUE
            ellipsize = null
            textSize = 16f
            val density = resources.displayMetrics.density
            setPadding((24 * density).toInt(), (14 * density).toInt(), (24 * density).toInt(), (14 * density).toInt())
            minimumHeight = (56 * density).toInt()
        }
}
