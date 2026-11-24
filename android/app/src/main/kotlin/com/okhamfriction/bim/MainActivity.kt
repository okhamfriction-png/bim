package com.okhamfriction.bim

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var launch: MethodChannel? = null
    private var dictate = false // ouverte par l'icône « Bim dictée », pas encore signalé à l'appli

    private fun fromDictee(i: Intent?) = i?.component?.className?.endsWith(".Dictee") == true

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // L'appli tourne déjà : on lui demande d'ouvrir le micro.
        if (fromDictee(intent)) launch?.invokeMethod("dicter", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dictate = fromDictee(intent)
        launch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bim/lancement")
        launch!!.setMethodCallHandler { call, result ->
            if (call.method == "dictee") {
                result.success(dictate)
                dictate = false
            } else result.notImplemented()
        }
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
