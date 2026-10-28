package app.mizu.iptv

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Détection Android TV : sert à réduire l'échelle du texte (l'interface
        // est pensée pour un écran de salon, pas pour un 1080p en xhdpi).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.mizu.iptv/ui")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> {
                        val mode = resources.configuration.uiMode and
                            Configuration.UI_MODE_TYPE_MASK
                        result.success(mode == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
