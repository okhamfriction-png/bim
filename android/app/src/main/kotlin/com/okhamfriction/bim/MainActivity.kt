package com.okhamfriction.bim

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // L'appli prévient le widget d'écran d'accueil quand ses données changent.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bim/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        BimWidget.refresh(applicationContext)
                        result.success(null)
                    }
                    // Réglages du widget : null tant que rien n'a été enregistré côté Android.
                    "config" -> result.success(
                        if (!WidgetPrefs.isSet(applicationContext)) null else mapOf(
                            "alpha" to WidgetPrefs.alpha(applicationContext),
                            "prios" to WidgetPrefs.prios(applicationContext)
                        )
                    )
                    "setConfig" -> {
                        WidgetPrefs.save(
                            applicationContext,
                            call.argument<Int>("alpha") ?: 100,
                            call.argument<List<Int>>("prios") ?: listOf(0, 1, 2, 3, 4)
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
