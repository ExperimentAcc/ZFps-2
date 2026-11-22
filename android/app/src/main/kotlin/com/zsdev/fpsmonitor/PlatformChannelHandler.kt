package com.zsdev.fpsmonitor

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Platform channel: com.zsdev.fpsmonitor/channel
 *
 * Methods:
 *  - getStorageDir               -> String (app private files dir, used by Hive)
 *  - checkShizuku                -> {ping, version, permission, bound, preV11}
 *  - bindShizuku                 -> Boolean (starts async bind + permission request)
 *  - runShell (command)          -> String (stdout+stderr, or "ERR: ...")
 *  - getStats (packageName,      -> {fps, cpuTemp, gpuTemp, freeRamMb, cpuUsage,
 *            includeStorage)        gpuUsage, storageSpeed, refreshRate}
 *  - getFrames (packageName,     -> {frames: List<Double> ms, valid: Boolean} new frame times
 *            reset)                  since the previous call (see FrameSampler)
 *  - getBatteryLevel             -> Int (0-100, or -1 when unknown)
 *  - checkOverlayPermission      -> Boolean (canDrawOverlays)
 *  - requestOverlayPermission    -> Boolean (opens system settings)
 *  - startMonitoring (appName)   -> Boolean (starts FGS + overlay)
 *  - stopMonitoring              -> Boolean
 *  - updateOverlay               -> Boolean (pushes live stats into the overlay)
 *  - getOverlayConfig / setOverlayConfig -> overlay look (see OverlayConfig)
 *  - getInstalledApps            -> List<Map{name, packageName, icon: Uint8List}>
 */
class PlatformChannelHandler(
    private val activity: MainActivity,
    messenger: BinaryMessenger
) {
    private val appContext = activity.applicationContext
    private val shizuku = ShizukuClient(appContext)
    private val metrics = SystemMetrics(appContext)
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "fps-metrics").apply { isDaemon = true }
    }

    // Separate thread so frame polling never waits behind the slower stats poll
    private val frameSampler = FrameSampler()
    private val frameExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "fps-frames").apply { isDaemon = true }
    }

    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler { call, result -> handle(call, result) }
    }

    fun register() {
        // Channel is registered eagerly in the property initializer above.
        Log.i(TAG, "Method channel registered: $CHANNEL")
    }

    // ------------------------------------------------------------- dispatch

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Storage folder for Hive (replaces path_provider)
            "getStorageDir" -> replyOnUi(result) { appContext.filesDir.absolutePath }

            "checkShizuku" -> replyOnUi(result) { shizuku.status() }

            "bindShizuku" -> replyOnUi(result) {
                shizuku.bind()
                true
            }

            "runShell" -> {
                val command = call.argument<String>("command") ?: ""
                executor.execute {
                    val output = shizuku.runShell(command)
                    replyOnUi(result) { output }
                }
            }

            "getStats" -> {
                val packageName = call.argument<String>("packageName") ?: ""
                val includeStorage = call.argument<Boolean>("includeStorage") ?: false
                executor.execute {
                    val stats = try {
                        metrics.collect(packageName, includeStorage, shizuku)
                    } catch (t: Throwable) {
                        Log.e(TAG, "collect() failed: ${t.message}")
                        fallbackStats()
                    }
                    replyOnUi(result) { stats }
                }
            }

            "getFrames" -> {
                val packageName = call.argument<String>("packageName") ?: ""
                val reset = call.argument<Boolean>("reset") ?: false
                frameExecutor.execute {
                    val batch = try {
                        frameSampler.poll(packageName, shizuku, reset)
                    } catch (t: Throwable) {
                        Log.e(TAG, "frame poll failed: ${t.message}")
                        FrameSampler.MISS
                    }
                    replyOnUi(result) {
                        mapOf("frames" to batch.frameTimesMs, "valid" to batch.valid)
                    }
                }
            }

            "getBatteryLevel" -> replyOnUi(result) { batteryLevelPercent() }

            "checkOverlayPermission" -> replyOnUi(result) { overlayPermitted() }

            "requestOverlayPermission" -> replyOnUi(result) {
                try {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${activity.packageName}")
                    )
                    activity.startActivity(intent)
                    true
                } catch (t: Throwable) {
                    Log.e(TAG, "open overlay settings failed: ${t.message}")
                    false
                }
            }

            "startMonitoring" -> replyOnUi(result) {
                val appName = call.argument<String>("appName") ?: "App"
                try {
                    MonitorService.start(appContext, appName)
                    true
                } catch (t: Throwable) {
                    Log.e(TAG, "startMonitoring failed: ${t.message}")
                    false
                }
            }

            "stopMonitoring" -> replyOnUi(result) {
                try {
                    MonitorService.stop(appContext)
                    true
                } catch (t: Throwable) {
                    Log.e(TAG, "stopMonitoring failed: ${t.message}")
                    false
                }
            }

            // Kept for compatibility with overlay-only flows
            "startOverlay" -> replyOnUi(result) {
                try {
                    OverlayService.start(appContext)
                    true
                } catch (t: Throwable) {
                    false
                }
            }

            "stopOverlay" -> replyOnUi(result) {
                OverlayService.stop(appContext)
                true
            }

            "updateOverlay" -> replyOnUi(result) {
                val fps = call.argument<Double>("fps") ?: -1.0
                val cpuTemp = call.argument<Double>("cpuTemp") ?: -1.0
                val gpuTemp = call.argument<Double>("gpuTemp") ?: -1.0
                val freeRam = call.argument<Double>("freeRamMb") ?: -1.0
                val cpuUsage = call.argument<Double>("cpuUsage") ?: -1.0
                val gpuUsage = call.argument<Double>("gpuUsage") ?: -1.0
                OverlayService.update(appContext, fps, cpuTemp, gpuTemp, freeRam, cpuUsage, gpuUsage)
                true
            }

            "getOverlayConfig" -> replyOnUi(result) { OverlayConfig.load(appContext).toMap() }

            "setOverlayConfig" -> replyOnUi(result) {
                val cfg = OverlayConfig.fromMap(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                cfg.save(appContext)
                try {
                    OverlayService.reloadConfig(appContext)
                } catch (t: Throwable) {
                    Log.w(TAG, "reloadConfig failed: ${t.message}")
                }
                true
            }

            "getInstalledApps" -> executor.execute {
                val apps = try {
                    metrics.launchableApps()
                } catch (t: Throwable) {
                    Log.e(TAG, "launchableApps failed: ${t.message}")
                    emptyList<Map<String, Any>>()
                }
                replyOnUi(result) { apps }
            }

            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------- helpers

    private fun replyOnUi(result: MethodChannel.Result, block: () -> Any?) {
        activity.runOnUiThread {
            try {
                result.success(block())
            } catch (t: Throwable) {
                Log.e(TAG, "channel call failed: ${t.message}")
                result.error("channel_error", t.message, null)
            }
        }
    }

    private fun overlayPermitted(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(activity)
        } else {
            true
        }

    private fun batteryLevelPercent(): Int {
        return try {
            val bm = appContext.getSystemService(BatteryManager::class.java)
            val property = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
            if (property in 0..100) {
                property
            } else {
                // Fallback: sticky battery intent
                @Suppress("DEPRECATION")
                val intent = appContext.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                if (intent != null) {
                    val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                    val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                    if (level >= 0 && scale > 0) level * 100 / scale else -1
                } else {
                    -1
                }
            }
        } catch (t: Throwable) {
            -1
        }
    }

    private fun fallbackStats(): Map<String, Any> = mapOf(
        "fps" to -1.0,
        "cpuTemp" to -1.0,
        "gpuTemp" to -1.0,
        "freeRamMb" to -1.0,
        "cpuUsage" to -1.0,
        "gpuUsage" to -1.0,
        "storageSpeed" to -1.0,
        "refreshRate" to 60.0
    )

    companion object {
        const val CHANNEL = "com.zsdev.fpsmonitor/channel"
        private const val TAG = "FpsChannel"
    }
}
