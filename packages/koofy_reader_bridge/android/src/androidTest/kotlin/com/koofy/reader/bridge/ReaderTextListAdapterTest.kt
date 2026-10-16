package com.koofy.reader.bridge

import android.content.Context
import android.view.ContextThemeWrapper
import android.widget.ListView
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReaderTextListAdapterTest {
    @Test fun newAndRecycledRowsAlwaysUseReadingThemeInsteadOfSystemTextColor() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val app = ApplicationProvider.getApplicationContext<Context>()
            for (systemTheme in listOf(android.R.style.Theme_Material, android.R.style.Theme_Material_Light)) {
                val context = ContextThemeWrapper(app, systemTheme)
                val parent = ListView(context)
                for (theme in listOf("light", "sepia", "dark")) {
                    val palette = ReaderPalette.forTheme(theme)
                    val adapter = ReaderTextListAdapter(context, listOf("첫 번째 장\n약 위치 1/40", "두 번째 장\n약 위치 8/40"), palette)
                    val first = adapter.getView(0, null, parent) as TextView
                    assertEquals("$theme on system theme $systemTheme", palette.foreground, first.currentTextColor)
                    val reused = adapter.getView(1, first, parent) as TextView
                    assertSame(first, reused)
                    assertEquals(palette.foreground, reused.currentTextColor)
                    assertTrue(reused.text.toString().contains("두 번째 장"))
                    assertTrue(reused.maxLines > 1)
                }
            }
        }
    }
}
