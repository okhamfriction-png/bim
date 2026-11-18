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
                if (call.method == "refresh") {
                    BimWidget.refresh(applicationContext)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
