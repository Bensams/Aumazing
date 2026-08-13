package com.example.aumazing

import android.content.pm.ActivityInfo
import android.content.res.Resources
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Hosts the Flutter engine and settles the orientation question before anything
 * else can get it wrong.
 *
 * Nothing that describes "the app's screen" can be trusted here, because once
 * Android letterboxes the app every such source shrinks with it. On a 2880x1800
 * tablet in the letterboxed state, `Resources.getSystem()`, the activity's own
 * `Configuration` and the Flutter window all report ~577dp — so the sw600dp
 * resource qualifier misses, the manifest falls back to the phone default, the
 * app asks for portrait, and the letterboxing it is trying to escape is exactly
 * what keeps it there.
 *
 * [maximumWindowMetrics] is the one source that stays honest: it reports the
 * bounds the window *could* occupy (the whole display), not the strip it has
 * been squeezed into. The startup orientation is decided from that, in
 * [onCreate], before the first frame — and the same number is handed to Dart so
 * the two layers cannot disagree.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Overrides the manifest's resource-qualified value, which is resolved
        // against the app's (possibly compat-shrunk) configuration.
        requestedOrientation = if (isTabletFormFactor()) {
            // Sensor, not user-landscape: a tablet turned around stays
            // landscape even with the rotation lock set to portrait.
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

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

    private fun isTabletFormFactor() =
        deviceSmallestScreenWidthDp() >= TABLET_SMALLEST_WIDTH_DP

    /** Smallest width of the whole display in dp, ignoring any letterboxing. */
    private fun deviceSmallestScreenWidthDp(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics = getSystemService(WindowManager::class.java).maximumWindowMetrics
            val bounds = metrics.bounds
            val density = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                metrics.density
            } else {
                resources.displayMetrics.density
            }
            if (density > 0f && bounds.width() > 0 && bounds.height() > 0) {
                return (min(bounds.width(), bounds.height()) / density).roundToInt()
            }
        }

        // Pre-R there is no maximum-window-metrics equivalent; the system
        // configuration is the best available answer.
        val system = Resources.getSystem()
        val fromConfig = system.configuration.smallestScreenWidthDp
        if (fromConfig > 0) return fromConfig

        val metrics = system.displayMetrics
        val density = if (metrics.density > 0f) metrics.density else 1f
        return (min(metrics.widthPixels, metrics.heightPixels) / density).roundToInt()
    }

    private companion object {
        const val CHANNEL = "aumazing/device_form_factor"

        /** Material breakpoint, matching `kTabletSmallestWidthDp` in Dart. */
        const val TABLET_SMALLEST_WIDTH_DP = 600
    }
}
