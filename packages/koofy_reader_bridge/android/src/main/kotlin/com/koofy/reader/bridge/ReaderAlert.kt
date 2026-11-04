package com.koofy.reader.bridge

import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.content.ContextWrapper
import android.content.DialogInterface
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.*
import androidx.core.view.ViewCompat
import java.util.ArrayDeque
import java.util.WeakHashMap

/** Native reader counterpart of Flutter's reader_alert.dart.
 * Reading panels stay panels; messages, choices and editors use this container.
 */
internal class ReaderAlert private constructor(
    context: Context, private val palette: ReaderPalette,
    private val heading: CharSequence?, private val message: CharSequence?,
    private val custom: View?, private val adapter: ListAdapter?, private val selected: Int?,
    private val choose: DialogInterface.OnClickListener?, private val actions: List<Action>,
    cancelable: Boolean,
) : Dialog(context) {
    private val owner = context
    private data class Action(val which: Int, val label: CharSequence, val click: DialogInterface.OnClickListener?)
    private val buttons = mutableMapOf<Int, Button>()
    private var queued = false
    private var afterDismiss: DialogInterface.OnDismissListener? = null
    private val status = TextView(context)
    val listView: ListView? = if (adapter != null) ListView(context) else null
    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
    private fun limitHeight(fraction: Float) = ((context.resources.displayMetrics.heightPixels - dp(48)) * fraction).toInt().coerceAtLeast(dp(48))

    init {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        setCancelable(cancelable)
        setCanceledOnTouchOutside(cancelable)
        super.setOnDismissListener { Queue.finished(this); afterDismiss?.onDismiss(this) }
    }

    override fun show() {
        if (!queued && !isShowing && alive()) { queued = true; Queue.add(this) }
    }

    private fun alive(): Boolean {
        var value = owner
        while (value is ContextWrapper && value !is Activity && value.baseContext !== value) value = value.baseContext
        return (value as? Activity)?.let { !it.isFinishing && !it.isDestroyed } ?: false
    }

    private fun present() {
        if (!alive()) { Queue.finished(this); return }
        super.show()
        val root = object : LinearLayout(context) {
            override fun onMeasure(width: Int, height: Int) {
                val available = if (View.MeasureSpec.getMode(height) == View.MeasureSpec.UNSPECIFIED)
                    limitHeight(1f) else minOf(limitHeight(1f), View.MeasureSpec.getSize(height))
                super.onMeasure(width, View.MeasureSpec.makeMeasureSpec(available, View.MeasureSpec.AT_MOST))
            }
        }.apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(palette.background); cornerRadius = dp(16).toFloat()
                setStroke(dp(1), (palette.secondary and 0x00ffffff) or 0x29000000)
            }
            clipToOutline = true
        }
        val body = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(20))
        }
        if (!heading.isNullOrEmpty()) body.addView(TextView(context).apply {
            text = heading; textSize = 18f; setTypeface(typeface, Typeface.BOLD)
            setTextColor(palette.foreground); setPadding(0, 0, 0, dp(12))
            ViewCompat.setAccessibilityHeading(this, true)
        })
        status.apply {
            text = message; textSize = 14f; setLineSpacing(0f, 1.55f)
            setTextColor(palette.foreground)
            visibility = if (message.isNullOrEmpty()) View.GONE else View.VISIBLE
        }
        body.addView(status)
        custom?.let {
            fun styleInputs(view: View) {
                if (view is EditText) {
                    view.setTextColor(palette.foreground); view.setHintTextColor(palette.secondary)
                    view.backgroundTintList = ColorStateList.valueOf(palette.accent)
                }
                if (view is ViewGroup) for (i in 0 until view.childCount) styleInputs(view.getChildAt(i))
            }
            styleInputs(it)
            (it.parent as? ViewGroup)?.removeView(it); body.addView(it, LinearLayout.LayoutParams(-1, -2))
        }
        if (listView == null) {
            root.addView(ScrollView(context).apply { addView(body) }, LinearLayout.LayoutParams(-1, -2, 1f))
        } else {
            root.addView(object : ScrollView(context) {
                override fun onMeasure(w: Int, h: Int) = super.onMeasure(w,
                    View.MeasureSpec.makeMeasureSpec(limitHeight(.3f), View.MeasureSpec.AT_MOST))
            }.apply { addView(body) }, LinearLayout.LayoutParams(-1, -2))
            listView.adapter = adapter
            listView.setBackgroundColor(palette.background)
            if (selected != null) { listView.choiceMode = ListView.CHOICE_MODE_SINGLE; listView.setItemChecked(selected, true) }
            listView.setOnItemClickListener { _, _, position, _ ->
                dismiss(); choose?.onClick(this, position)
            }
            root.addView(listView, LinearLayout.LayoutParams(-1, -2, 1f))
        }
        root.addView(View(context).apply { setBackgroundColor((palette.secondary and 0x00ffffff) or 0x29000000) }, LinearLayout.LayoutParams(-1, dp(1)))
        val vertical = actions.size > 2 || context.resources.configuration.fontScale > 1.4f
        val footer = LinearLayout(context).apply {
            orientation = if (vertical) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
            setPadding(dp(8), dp(4), dp(8), dp(4))
        }
        actions.forEach { action ->
            val button = getButton(action.which)
            (button.parent as? ViewGroup)?.removeView(button)
            footer.addView(button, if (vertical) LinearLayout.LayoutParams(-1, -2) else LinearLayout.LayoutParams(0, -2, 1f))
        }
        root.addView(object : ScrollView(context) {
            override fun onMeasure(w: Int, h: Int) = super.onMeasure(w,
                View.MeasureSpec.makeMeasureSpec(limitHeight(.45f), View.MeasureSpec.AT_MOST))
        }.apply { addView(footer) }, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
        window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            attributes = attributes.apply { dimAmount = .28f; gravity = Gravity.CENTER }
            setLayout(minOf(context.resources.displayMetrics.widthPixels - dp(48), dp(440)), ViewGroup.LayoutParams.WRAP_CONTENT)
            clearFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        }
    }

    fun setMessage(value: CharSequence) { status.text = value; status.visibility = View.VISIBLE }
    fun getButton(which: Int): Button = buttons.getOrPut(which) {
        val action = requireNotNull(actions.firstOrNull { it.which == which })
        Button(context).apply {
            text = action.label; isAllCaps = false; textSize = 14f
            setTypeface(typeface, Typeface.BOLD); minHeight = dp(48); minimumHeight = dp(48)
            minWidth = 0; minimumWidth = 0; setPadding(dp(12), dp(12), dp(12), dp(12))
            setTextColor(palette.accent)
            background = RippleDrawable(ColorStateList.valueOf((palette.accent and 0x00ffffff) or 0x18000000),
                GradientDrawable().apply { setColor(Color.TRANSPARENT); cornerRadius = dp(6).toFloat() }, null)
            setOnClickListener { dismiss(); action.click?.onClick(this@ReaderAlert, action.which) }
        }
    }
    override fun setOnDismissListener(listener: DialogInterface.OnDismissListener?) { afterDismiss = listener }
    companion object { fun dismissAll(owner: Context) = Queue.clear(owner) }

    class Builder(private val context: Context, private val palette: ReaderPalette) {
        private var title: CharSequence? = null
        private var message: CharSequence? = null
        private var custom: View? = null
        private var adapter: ListAdapter? = null
        private var selected: Int? = null
        private var choose: DialogInterface.OnClickListener? = null
        private var cancelable = true
        private val actions = mutableListOf<Action>()
        fun setTitle(value: CharSequence) = apply { title = value }
        fun setMessage(value: CharSequence) = apply { message = value }
        fun setView(value: View) = apply { custom = value }
        fun setCancelable(value: Boolean) = apply { cancelable = value }
        fun setAdapter(value: ListAdapter, click: DialogInterface.OnClickListener) = apply { adapter = value; choose = click }
        fun setSingleChoiceItems(value: ListAdapter, checked: Int, click: DialogInterface.OnClickListener) = apply {
            adapter = value; selected = checked; choose = click
        }
        fun setPositiveButton(label: CharSequence, click: DialogInterface.OnClickListener?) = apply {
            actions.add(Action(DialogInterface.BUTTON_POSITIVE, label, click))
        }
        fun setNegativeButton(label: CharSequence, click: DialogInterface.OnClickListener?) = apply {
            actions.add(0, Action(DialogInterface.BUTTON_NEGATIVE, label, click))
        }
        fun create(): ReaderAlert = ReaderAlert(context, palette, title, message, custom, adapter, selected, choose,
            actions.ifEmpty { listOf(Action(DialogInterface.BUTTON_NEGATIVE, L("닫기"), null)) }.toList(), cancelable)
        fun show(): ReaderAlert = create().also { it.show() }
    }

    private object Queue {
        private val rows = WeakHashMap<Context, ArrayDeque<ReaderAlert>>()
        private val closing = WeakHashMap<Context, Boolean>()
        private val main = Handler(Looper.getMainLooper())
        fun add(alert: ReaderAlert) {
            if (closing[alert.owner] == true) return
            val queue = rows.getOrPut(alert.owner) { ArrayDeque() }
            queue.add(alert)
            if (queue.size == 1) alert.present()
        }
        fun finished(alert: ReaderAlert) {
            val queue = rows[alert.owner] ?: return
            if (!queue.remove(alert)) return
            alert.queued = false
            if (queue.isEmpty()) rows.remove(alert.owner)
            else main.post { queue.peek()?.present() }
        }
        fun clear(owner: Context) { closing[owner] = true; rows.remove(owner)?.toList()?.forEach { it.dismiss() } }
    }
}
