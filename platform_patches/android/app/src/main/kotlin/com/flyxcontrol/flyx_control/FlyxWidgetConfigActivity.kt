package com.flyxcontrol.flyx_control

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

class FlyxWidgetConfigActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private val metricBoxes = linkedMapOf<String, CheckBox>()
    private lateinit var styleGroup: RadioGroup
    private lateinit var themeGroup: RadioGroup

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        window.statusBarColor = Color.parseColor("#0B0D10")
        window.navigationBarColor = Color.parseColor("#0B0D10")
        setContentView(buildContent())
        restoreConfiguration()
    }

    private fun buildContent(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(28))
            setBackgroundColor(Color.parseColor("#0B0D10"))
        }

        root.addView(text("FlyX widget", 28f, Color.WHITE, Typeface.BOLD))
        root.addView(
            text(
                "Choose a layout and up to four router details. You can add more than one FlyX widget and configure each one differently.",
                14f,
                Color.parseColor("#A8B0BB"),
                Typeface.NORMAL,
            ).withTop(dp(8)),
        )

        root.addView(section("DESIGN").withTop(dp(28)))
        styleGroup = RadioGroup(this).apply { orientation = RadioGroup.VERTICAL }
        listOf(
            Triple(101, "Focus", "One large stat with supporting details"),
            Triple(102, "Overview", "Balanced dashboard card"),
            Triple(103, "Split", "Two strong columns with compact extras"),
            Triple(104, "Grid", "Up to four equally weighted tiles"),
            Triple(105, "Stack", "Clean vertical list for quick scanning"),
        ).forEach { (id, name, description) ->
            styleGroup.addView(choiceRadio(id, name, description))
        }
        root.addView(styleGroup)

        root.addView(section("DETAILS · SELECT 1–4").withTop(dp(28)))
        listOf(
            "download" to "Download",
            "upload" to "Upload",
            "devices" to "Connected devices",
            "uptime" to "Router uptime",
            "messages" to "Messages",
            "today" to "Usage today",
            "month" to "Usage this month",
        ).forEach { (key, label) ->
            val box = CheckBox(this).apply {
                text = label
                textSize = 15f
                setTextColor(Color.WHITE)
                buttonTintList = ColorStateList(
                    arrayOf(
                        intArrayOf(android.R.attr.state_checked),
                        intArrayOf(),
                    ),
                    intArrayOf(
                        Color.parseColor("#FFCB05"),
                        Color.parseColor("#667085"),
                    ),
                )
                setPadding(dp(2), dp(7), 0, dp(7))
                setOnCheckedChangeListener { button, checked ->
                    if (checked && selectedMetrics().size > 4) {
                        button.isChecked = false
                        Toast.makeText(
                            this@FlyxWidgetConfigActivity,
                            "A widget can show a maximum of four details.",
                            Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            }
            metricBoxes[key] = box
            root.addView(box)
        }

        root.addView(section("THEME").withTop(dp(28)))
        themeGroup = RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        listOf(
            201 to "System",
            202 to "Light",
            203 to "Dark",
        ).forEach { (id, label) ->
            val button = RadioButton(this).apply {
                this.id = id
                text = label
                textSize = 14f
                setTextColor(Color.WHITE)
                buttonTintList = ColorStateList(
                    arrayOf(
                        intArrayOf(android.R.attr.state_checked),
                        intArrayOf(),
                    ),
                    intArrayOf(
                        Color.parseColor("#FFCB05"),
                        Color.parseColor("#667085"),
                    ),
                )
            }
            themeGroup.addView(
                button,
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
        }
        root.addView(themeGroup)

        val save = Button(this).apply {
            text = "Add widget"
            isAllCaps = false
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#0B0D10"))
            background = rounded(Color.parseColor("#FFCB05"), 16f)
            setOnClickListener { saveAndFinish() }
        }
        root.addView(
            save,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(54),
            ).apply { topMargin = dp(30) },
        )

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            addView(root)
        }
        return scroll
    }

    private fun choiceRadio(id: Int, title: String, description: String): RadioButton {
        return RadioButton(this).apply {
            this.id = id
            text = "$title\n$description"
            textSize = 15f
            setTextColor(Color.WHITE)
            setLineSpacing(dp(3).toFloat(), 1f)
            setPadding(dp(2), dp(8), 0, dp(8))
            buttonTintList = ColorStateList(
                arrayOf(
                    intArrayOf(android.R.attr.state_checked),
                    intArrayOf(),
                ),
                intArrayOf(
                    Color.parseColor("#FFCB05"),
                    Color.parseColor("#667085"),
                ),
            )
        }
    }

    private fun restoreConfiguration() {
        val prefs = getSharedPreferences(FlyxWidgetProvider.CONFIG_PREFS, MODE_PRIVATE)
        when (prefs.getString(key("style"), "overview")) {
            "focus" -> styleGroup.check(101)
            "split" -> styleGroup.check(103)
            "grid" -> styleGroup.check(104)
            "stack" -> styleGroup.check(105)
            else -> styleGroup.check(102)
        }

        val savedMetrics = prefs.getString(key("metrics"), null)
            ?.split(',')
            ?.toSet()
            ?: setOf("download", "upload", "devices", "today")
        metricBoxes.forEach { (metric, box) -> box.isChecked = metric in savedMetrics }

        when (prefs.getString(key("theme"), "system")) {
            "light" -> themeGroup.check(202)
            "dark" -> themeGroup.check(203)
            else -> themeGroup.check(201)
        }
    }

    private fun saveAndFinish() {
        val metrics = selectedMetrics()
        if (metrics.isEmpty()) {
            Toast.makeText(this, "Select at least one detail.", Toast.LENGTH_SHORT).show()
            return
        }

        val style = when (styleGroup.checkedRadioButtonId) {
            101 -> "focus"
            103 -> "split"
            104 -> "grid"
            105 -> "stack"
            else -> "overview"
        }
        val theme = when (themeGroup.checkedRadioButtonId) {
            202 -> "light"
            203 -> "dark"
            else -> "system"
        }

        getSharedPreferences(FlyxWidgetProvider.CONFIG_PREFS, MODE_PRIVATE)
            .edit()
            .putString(key("style"), style)
            .putString(key("theme"), theme)
            .putString(key("metrics"), metrics.joinToString(","))
            .apply()

        FlyxWidgetProvider.updateWidget(
            this,
            AppWidgetManager.getInstance(this),
            appWidgetId,
        )

        val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(RESULT_OK, result)
        finish()
    }

    private fun selectedMetrics(): List<String> = metricBoxes
        .filterValues { it.isChecked }
        .keys
        .take(4)

    private fun key(suffix: String) = "widget_${appWidgetId}_$suffix"

    private fun section(value: String) = text(
        value,
        12f,
        Color.parseColor("#FFCB05"),
        Typeface.BOLD,
    )

    private fun text(value: String, size: Float, color: Int, weight: Int) =
        TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            setTypeface(typeface, weight)
        }

    private fun View.withTop(value: Int): View = apply {
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = value }
    }

    private fun rounded(color: Int, radiusDp: Float) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp.toInt()).toFloat()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
