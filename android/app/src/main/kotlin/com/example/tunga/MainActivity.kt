package com.example.tunga

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.tunga/config"
        ).setMethodCallHandler { call, result ->
            val appInfo = packageManager.getApplicationInfo(
                packageName,
                android.content.pm.PackageManager.GET_META_DATA
            )
            when (call.method) {
                "getMapsApiKey" -> {
                    val apiKey = appInfo.metaData?.getString("com.google.android.geo.API_KEY") ?: ""
                    result.success(apiKey)
                }
                    "getWeatherApiKey" -> {
                    val apiKey = appInfo.metaData?.getString("com.example.tunga.WEATHER_API_KEY") ?: ""
                    result.success(apiKey)
                }
                "getCustomSearchApiKey" -> {
                    val apiKey = appInfo.metaData?.getString("com.example.tunga.CUSTOM_SEARCH_API_KEY") ?: ""
                    result.success(apiKey)
                }
                "getCustomSearchEngineId" -> {
                    val engineId = appInfo.metaData?.getString("com.example.tunga.CUSTOM_SEARCH_ENGINE_ID") ?: ""
                    result.success(engineId)
                }
                "getAiApiKey" -> {
                    val apiKey = appInfo.metaData?.getString("com.example.tunga.AI_API_KEY") ?: ""
                    result.success(apiKey)
                }
                else -> result.notImplemented()
            }
        }
    }
}
