package com.example.aumazing

import android.content.res.Resources
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Hosts the Flutter engine and answers "how wide is this *device*?".
 *
 * Dart cannot answer that on its own: once Android letterboxes the app into a
 * portrait strip, the Flutter window reports the strip (~577dp on a 2880x1800
 * tablet), so a size check there would classify a tablet as a phone and lock
 * portrait — keeping it letterboxed forever. The value below comes from the
 * system resources, which are never adjusted for the app's compat/letterbox
 * state, so it matches the sw600dp qualifier Android used to pick the
 * activity's startup orientation from the manifest.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "smallestScreenWidthDp" -> result.success(deviceSmallestScreenWidthDp())
                    else -> result.notImplemented()
                }
            }
    }

    /** Smallest screen width of the physical display, in dp. */
    private fun deviceSmallestScreenWidthDp(): Int {
        val system = Resources.getSystem()
        val fromConfig = system.configuration.smallestScreenWidthDp
        if (fromConfig > 0) return fromConfig

        // Configuration.smallestScreenWidthDp is unset on some OEM builds;
        // derive it from the raw display metrics instead.
        val metrics = system.displayMetrics
        val density = if (metrics.density > 0f) metrics.density else 1f
        return (min(metrics.widthPixels, metrics.heightPixels) / density).roundToInt()
    }

    private companion object {
        const val CHANNEL = "aumazing/device_form_factor"
    }
}
