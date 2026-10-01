package com.flyxcontrol.flyx_control

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sync" -> {
                    val values = call.arguments as? Map<*, *>
                    if (values == null) {
                        result.error("BAD_WIDGET_DATA", "Widget data was missing.", null)
                        return@setMethodCallHandler
                    }

                    val prefs = getSharedPreferences(
                        FlyxWidgetProvider.DATA_PREFS,
                        MODE_PRIVATE,
                    )
                    val editor = prefs.edit()
                    listOf(
                        "download",
                        "upload",
                        "devices",
                        "uptime",
                        "messages",
                        "today",
                        "month",
                    ).forEach { key ->
                        editor.putString(key, values[key]?.toString() ?: "—")
                    }
                    editor.putBoolean("connected", values["connected"] as? Boolean ?: false)
                    editor.putLong(
                        "updatedAt",
                        (values["updatedAt"] as? Number)?.toLong()
                            ?: System.currentTimeMillis(),
                    )
                    editor.apply()

                    FlyxWidgetProvider.updateAll(this)
                    result.success(null)
                }

                "requestPinWidget" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val manager = AppWidgetManager.getInstance(this)
                    if (!manager.isRequestPinAppWidgetSupported) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val provider = ComponentName(this, FlyxWidgetProvider::class.java)
                    result.success(manager.requestPinAppWidget(provider, null, null))
                }

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val WIDGET_CHANNEL = "com.flyxcontrol.flyx_control/widgets"
    }
}
