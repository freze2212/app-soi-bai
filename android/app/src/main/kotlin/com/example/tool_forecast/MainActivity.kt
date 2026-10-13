package com.example.tool_forecast

/**
 * Overlay “vẽ trên app khác” do plugin [flutter_overlay_window] (bản fork trong
 * `packages/flutter_overlay_window`) xử lý: kéo thả native + giới hạn trong màn hình
 * trong [flutter.overlay.window.flutter_overlay_window.OverlayService].
 */
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.tool_forecast/app",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveTaskToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
