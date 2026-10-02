package com.flyxcontrol.flyx_control

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews

class FlyxWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = context.getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE).edit()
        appWidgetIds.forEach { appWidgetId ->
            editor.remove(configKey(appWidgetId, "style"))
            editor.remove(configKey(appWidgetId, "theme"))
            editor.remove(configKey(appWidgetId, "metrics"))
        }
        editor.apply()
    }

    companion object {
        const val DATA_PREFS = "flyx_widget_data"
        const val CONFIG_PREFS = "flyx_widget_config"

        private val defaultMetrics = listOf("download", "upload", "devices", "today")
        private val metricLabels = mapOf(
            "download" to "Download",
            "upload" to "Upload",
            "devices" to "Devices",
            "uptime" to "Router uptime",
            "messages" to "Messages",
            "today" to "Usage today",
            "month" to "This month",
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, FlyxWidgetProvider::class.java),
            )
            ids.forEach { updateWidget(context, manager, it) }
        }

        fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val config = context.getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)
            val data = context.getSharedPreferences(DATA_PREFS, Context.MODE_PRIVATE)
            val style = config.getString(configKey(appWidgetId, "style"), "overview")
                ?: "overview"
            val theme = config.getString(configKey(appWidgetId, "theme"), "system")
                ?: "system"
            val metrics = config.getString(configKey(appWidgetId, "metrics"), null)
                ?.split(',')
                ?.filter { metricLabels.containsKey(it) }
                ?.take(4)
                ?.ifEmpty { defaultMetrics }
                ?: defaultMetrics

            val layout = when (style) {
                "focus" -> R.layout.widget_focus
                "split" -> R.layout.widget_split
                "grid" -> R.layout.widget_grid
                "stack" -> R.layout.widget_stack
                else -> R.layout.widget_overview
            }
            val views = RemoteViews(context.packageName, layout)

            val useDark = when (theme) {
                "dark" -> true
                "light" -> false
                else -> (context.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            }

            applyTheme(views, useDark, style)
            applyData(context, views, metrics, data, style, useDark)
            manager.updateAppWidget(appWidgetId, views)
        }

        private fun applyTheme(views: RemoteViews, dark: Boolean, style: String) {
            val text = Color.parseColor(if (dark) "#F7F8FA" else "#171A1F")
            val muted = Color.parseColor(if (dark) "#959DA8" else "#667085")
            val brand = Color.parseColor(if (dark) "#FFCB05" else "#8A6800")
            val background = if (dark) R.drawable.widget_bg_dark else R.drawable.widget_bg_light
            val cell = if (dark) R.drawable.widget_cell_dark else R.drawable.widget_cell_light

            views.setInt(R.id.widget_root, "setBackgroundResource", background)
            views.setTextColor(R.id.widget_title, brand)
            views.setTextColor(R.id.widget_status, muted)

            for (index in 1..4) {
                views.setTextColor(labelId(index), muted)
                views.setTextColor(valueId(index), text)
                views.setTextColor(unitId(index), text)
            }

            if (style == "grid") {
                for (index in 1..4) {
                    views.setInt(metricContainerId(index), "setBackgroundResource", cell)
                }
            }
        }

        private fun applyData(
            context: Context,
            views: RemoteViews,
            metrics: List<String>,
            data: android.content.SharedPreferences,
            style: String,
            dark: Boolean,
        ) {
            val connected = data.getBoolean("connected", false)
            views.setTextViewText(R.id.widget_title, "FLYX CONTROL")
            views.setTextViewText(
                R.id.widget_status,
                if (connected) "● ONLINE" else "● OFFLINE",
            )
            views.setTextColor(
                R.id.widget_status,
                Color.parseColor(if (connected) "#2E9A58" else "#9B1C1C"),
            )

            for (index in 1..4) {
                val metric = metrics.getOrNull(index - 1)
                val containerId = metricContainerId(index)
                if (metric == null) {
                    views.setViewVisibility(containerId, View.GONE)
                    continue
                }

                views.setViewVisibility(containerId, View.VISIBLE)
                val rawValue = data.getString(metric, "—") ?: "—"
                val displayValue = if (metric == "messages") {
                    if (rawValue == "0") "All read" else "$rawValue unread"
                } else {
                    rawValue
                }
                views.setTextViewText(labelId(index), metricLabels[metric] ?: metric)
                if (metric == "download" || metric == "upload") {
                    val rate = splitRate(displayValue)
                    views.setTextViewText(valueId(index), rate.first)
                    views.setTextViewText(unitId(index), rate.second)
                    views.setViewVisibility(unitId(index), View.VISIBLE)
                } else {
                    views.setTextViewText(valueId(index), displayValue)
                    views.setTextViewText(unitId(index), "")
                    views.setViewVisibility(unitId(index), View.GONE)
                }
            }

            when (style) {
                "focus" -> {
                    views.setViewVisibility(
                        R.id.widget_secondary_metrics,
                        if (metrics.size > 1) View.VISIBLE else View.GONE,
                    )
                }
                "overview" -> {
                    val showSecondary = metrics.size > 2
                    views.setViewVisibility(
                        R.id.widget_secondary_metrics,
                        if (showSecondary) View.VISIBLE else View.GONE,
                    )
                    views.setViewVisibility(
                        R.id.widget_secondary_divider,
                        if (showSecondary) View.VISIBLE else View.GONE,
                    )
                }
                "split" -> {
                    views.setViewVisibility(
                        R.id.widget_primary_divider,
                        if (metrics.size > 1) View.VISIBLE else View.GONE,
                    )
                    views.setViewVisibility(
                        R.id.widget_secondary_metrics,
                        if (metrics.size > 2) View.VISIBLE else View.GONE,
                    )
                }
                "grid" -> {
                    views.setViewVisibility(
                        R.id.widget_primary_gap,
                        if (metrics.size > 1) View.VISIBLE else View.GONE,
                    )
                    views.setViewVisibility(
                        R.id.widget_secondary_metrics,
                        if (metrics.size > 2) View.VISIBLE else View.GONE,
                    )
                    views.setViewVisibility(
                        R.id.widget_secondary_gap,
                        if (metrics.size > 3) View.VISIBLE else View.GONE,
                    )
                }
            }

            val openApp = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                openApp,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        }

        private fun splitRate(value: String): Pair<String, String> {
            val match = Regex("""^(.+?)\s+(bps|Kbps|Mbps|Gbps)$""").matchEntire(value)
                ?: return value to ""
            return match.groupValues[1] to match.groupValues[2]
        }

        private fun configKey(appWidgetId: Int, suffix: String) =
            "widget_${appWidgetId}_$suffix"

        private fun metricContainerId(index: Int) = when (index) {
            1 -> R.id.metric1
            2 -> R.id.metric2
            3 -> R.id.metric3
            else -> R.id.metric4
        }

        private fun labelId(index: Int) = when (index) {
            1 -> R.id.metric1_label
            2 -> R.id.metric2_label
            3 -> R.id.metric3_label
            else -> R.id.metric4_label
        }

        private fun valueId(index: Int) = when (index) {
            1 -> R.id.metric1_value
            2 -> R.id.metric2_value
            3 -> R.id.metric3_value
            else -> R.id.metric4_value
        }

        private fun unitId(index: Int) = when (index) {
            1 -> R.id.metric1_unit
            2 -> R.id.metric2_unit
            3 -> R.id.metric3_unit
            else -> R.id.metric4_unit
        }
    }
}
