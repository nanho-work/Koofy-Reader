package com.koofy.reader.bridge

internal object ReaderTheme {
    private var context: android.content.Context? = null
    fun initialize(value: android.content.Context) { context = value.applicationContext }
    fun resolve(theme: String): String {
        if (theme != "app") return theme
        val c = context
        val mode = c?.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)?.getString("flutter.app_theme_v1", "system")
        if (mode == "light" || mode == "dark" || mode == "sepia") return mode
        val config = c?.resources?.configuration ?: android.content.res.Resources.getSystem().configuration
        return if (config.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES) "dark" else "light"
    }
}
