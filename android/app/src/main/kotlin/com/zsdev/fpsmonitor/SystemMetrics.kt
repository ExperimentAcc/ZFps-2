package com.zsdev.fpsmonitor

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Log
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.Random

/**
 * Collects runtime performance metrics.
 *
 * Sources (in order of preference):
 *  - CPU / GPU temperature ......... kernel thermal zones (/sys/class/thermal) via Shizuku shell
 *  - Free RAM ...................... MemAvailable from /proc/meminfo via shell, ActivityManager fallback
 *  - CPU usage % ................... delta between two /proc/stat samples
 *  - GPU usage % ................... Qualcomm kgsl gpu_busy_percentage, gpubusy ratio, Mali fallback
 *  - FPS ........................... SurfaceFlinger frame timestamps (via shell) clamped to the
 *                                    display refresh rate; falls back to refresh rate when unavailable
 *  - Storage speed ................. app-side sequential write benchmark (no root needed)
 */
class SystemMetrics(private val context: Context) {

    // ---- cached / stateful bits ----
    @Volatile
    private var lastStorageSpeedMbps: Double = -1.0

    private var prevCpuTotal: Long = -1
    private var prevCpuIdle: Long = -1

    @Volatile private var lastHal: Map<Int, List<Double>> = emptyMap()
    @Volatile private var lastHalAt: Long = 0L
    @Volatile private var loggedThermalMiss = false

    private companion object {
        const val TAG = "FpsThermal"
        const val HAL_CACHE_MS = 5000L
        const val HAL_CPU = 0
        const val HAL_GPU = 1
        const val HAL_BATTERY = 2
        const val HAL_SKIN = 3

        val GPU_SENSOR = Regex("gpu|kgsl|gpuss|g3d|mali|adreno")
        val CPU_SENSOR = Regex("cpu|cpuss|acpu|apcpu|cluster|silver|gold|prime|kryo|tsens|soc_|big|little|mtktscpu|mtk-cpu")
        val IGNORED_SENSOR = Regex("batt|bat_|charger|usb|pmic|pm8|pm6|wlan|modem|mdm|quiet|ambient|flash|camera|display|lcd|sdm|nand|ufs|wireless")

        // One shell call: thermal zones + hwmon sensors + Adreno temp ("name=value" lines)
        const val THERMAL_SCRIPT =
            "for z in /sys/class/thermal/thermal_zone*; do " +
                "t=\$(cat \$z/type 2>/dev/null); v=\$(cat \$z/temp 2>/dev/null); " +
                "[ -n \"\$v\" ] && echo \"\$t=\$v\"; done; " +
                "for h in /sys/class/hwmon/hwmon*; do " +
                "n=\$(cat \$h/name 2>/dev/null); v=\$(cat \$h/temp1_input 2>/dev/null); " +
                "[ -n \"\$v\" ] && echo \"hwmon_\$n=\$v\"; done; " +
                "v=\$(cat /sys/class/kgsl/kgsl-3d0/temp 2>/dev/null); " +
                "[ -n \"\$v\" ] && echo \"kgsl_gpu=\$v\"; true"
    }

    // ------------------------------------------------------------------ collect

    fun collect(packageName: String, includeStorage: Boolean, shizuku: ShizukuClient): Map<String, Any> {
        val refreshRate = displayRefreshRate()
        val fps = estimateFps(packageName, refreshRate, shizuku)
        val temps = readThermalTemps(shizuku)
        val freeRam = readFreeRamMb(shizuku)
        val cpuUsage = readCpuUsagePercent(shizuku)
        val gpuUsage = readGpuUsagePercent(shizuku)

        val storage = if (includeStorage) {
            benchmarkStorageSpeed()
        } else if (lastStorageSpeedMbps > 0) {
            lastStorageSpeedMbps
        } else {
            -1.0
        }

        return mapOf(
            "fps" to fps,
            "cpuTemp" to temps.first,
            "gpuTemp" to temps.second,
            "freeRamMb" to freeRam,
            "cpuUsage" to cpuUsage,
            "gpuUsage" to gpuUsage,
            "storageSpeed" to storage,
            "refreshRate" to refreshRate
        )
    }

    // ------------------------------------------------------------------ installed apps

    data class InstalledApp(
        val name: String,
        val packageName: String,
        val iconPng: ByteArray
    )

    fun launchableApps(): List<Map<String, Any>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = try {
            pm.queryIntentActivities(intent, 0)
        } catch (t: Throwable) {
            emptyList()
        }
        val iconSizePx = 96
        return resolved
            .mapNotNull { ri ->
                val pkg = ri.activityInfo?.packageName ?: return@mapNotNull null
                if (pkg == context.packageName) return@mapNotNull null
                val label = try {
                    ri.loadLabel(pm)?.toString()?.takeIf { it.isNotBlank() } ?: pkg
                } catch (t: Throwable) {
                    pkg
                }
                val icon = try {
                    drawableToPng(ri.loadIcon(pm), iconSizePx)
                } catch (t: Throwable) {
                    ByteArray(0)
                }
                mapOf(
                    "name" to label,
                    "packageName" to pkg,
                    "icon" to icon
                )
            }
            .sortedBy { (it["name"] as String).lowercase() }
    }

    private fun drawableToPng(drawable: Drawable, sizePx: Int): ByteArray {
        val bitmap = when (drawable) {
            is BitmapDrawable -> drawable.bitmap?.let { Bitmap.createScaledBitmap(it, sizePx, sizePx, true) }
            else -> {
                val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, sizePx, sizePx)
                drawable.draw(canvas)
                bmp
            }
        } ?: Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)

        val scaled = if (bitmap.width != sizePx || bitmap.height != sizePx) {
            Bitmap.createScaledBitmap(bitmap, sizePx, sizePx, true)
        } else {
            bitmap
        }
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.PNG, 90, out)
        return out.toByteArray()
    }

    // ------------------------------------------------------------------ FPS

    private fun displayRefreshRate(): Double {
        return try {
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
                ?: return 60.0
            @Suppress("DEPRECATION")
            val rate = wm.defaultDisplay?.refreshRate?.toDouble() ?: 60.0
            if (rate in 20.0..500.0) rate else 60.0
        } catch (t: Throwable) {
            60.0
        }
    }

    /**
     * Estimate FPS for [packageName].
     *
     * Uses `dumpsys SurfaceFlinger --latency <layer>` which prints recent frame
     * presentation timestamps (nanoseconds). fps = frames / time-span. The
     * result is clamped to the display refresh rate. Falls back to the refresh
     * rate when the layer cannot be located (e.g. game in background).
     */
    private fun estimateFps(packageName: String, refreshRate: Double, shizuku: ShizukuClient): Double {
        return try {
            val safePkg = packageName.replace(Regex("[^A-Za-z0-9_.]"), "")
            if (safePkg.isEmpty()) return refreshRate
            val script =
                "S=\$(dumpsys SurfaceFlinger | grep -i -m1 '$safePkg' | sed 's/^[[:space:]]*//' | cut -d' ' -f1); " +
                    "if [ -n \"\$S\" ]; then dumpsys SurfaceFlinger --latency \"\$S\"; else echo NA; fi"
            val out = shizuku.runShell(script)
            if (out.startsWith("ERR") || out.trim() == "NA" || out.isBlank()) {
                return refreshRate
            }
            // Keep only plausible nanosecond timestamps (> ~2001 in ns)
            val ts = Regex("[0-9]+").findAll(out)
                .map { it.value.toLong() }
                .filter { it > 1_000_000_000_000L }
                .toList()
            if (ts.size < 2) return refreshRate
            val window = ts.takeLast(120)
            val span = window.last() - window.first()
            if (span <= 0) return refreshRate
            val fps = (window.size - 1).toDouble() * 1_000_000_000.0 / span.toDouble()
            fps.coerceIn(0.0, refreshRate + 1.0)
        } catch (t: Throwable) {
            refreshRate
        }
    }

    // ------------------------------------------------------------------ temperatures

    /**
     * Reads CPU / GPU temperature from several sources, best first:
     *  1. kernel thermal zones, hwmon sensors and kgsl temp (via Shizuku shell)
     *  2. Android thermal HAL (`dumpsys thermalservice`) - works on most phones
     *     where the sysfs files are hidden or use odd units
     *  3. last resort: skin / battery temperature so the UI is never blank
     * Returns Pair(cpuCelsius, gpuCelsius); -1 when unknown.
     */
    private fun readThermalTemps(shizuku: ShizukuClient): Pair<Double, Double> {
        val cpuTemps = mutableListOf<Double>()
        val gpuTemps = mutableListOf<Double>()
        val allTemps = mutableListOf<Double>()

        val zonesOut = try {
            shizuku.runShell(THERMAL_SCRIPT)
        } catch (t: Throwable) {
            ""
        }

        zonesOut.lineSequence().forEach { line ->
            val idx = line.indexOf('=')
            if (idx <= 0) return@forEach
            val type = line.substring(0, idx).trim().lowercase()
            val raw = line.substring(idx + 1).trim().toDoubleOrNull() ?: return@forEach
            val celsius = normalizeCelsius(raw) ?: return@forEach
            if (IGNORED_SENSOR.containsMatchIn(type)) return@forEach
            allTemps.add(celsius)
            when {
                GPU_SENSOR.containsMatchIn(type) -> gpuTemps.add(celsius)
                CPU_SENSOR.containsMatchIn(type) -> cpuTemps.add(celsius)
            }
        }

        // Thermal HAL: only queried when sysfs did not give both values
        val hal = if (cpuTemps.isEmpty() || gpuTemps.isEmpty()) readHalTemps(shizuku) else emptyMap()

        val cpu = cpuTemps.averageOrNull()
            ?: hal[HAL_CPU]?.averageOrNull()
            ?: allTemps.averageOrNull()
            ?: hal[HAL_SKIN]?.averageOrNull()
            ?: hal[HAL_BATTERY]?.averageOrNull()
            ?: batteryTempC()
        val gpu = gpuTemps.averageOrNull()
            ?: hal[HAL_GPU]?.averageOrNull()
            ?: allTemps.averageOrNull()
            ?: hal[HAL_SKIN]?.averageOrNull()
            ?: hal[HAL_BATTERY]?.averageOrNull()
            ?: batteryTempC()

        if (cpu == null && gpu == null && !loggedThermalMiss) {
            loggedThermalMiss = true
            Log.w(TAG, "No temperature source worked. zones output: ${zonesOut.take(300)}")
        }
        return (cpu ?: -1.0) to (gpu ?: -1.0)
    }

    /** Handles milli-degrees (45000), deci-degrees (450) and plain degrees (45). */
    private fun normalizeCelsius(raw: Double): Double? {
        val c = when {
            raw > 1000.0 -> raw / 1000.0
            raw > 150.0 -> raw / 10.0
            else -> raw
        }
        return if (c in 1.0..125.0) c else null
    }

    /** `dumpsys thermalservice` -> map of HAL type id to temperatures (Celsius). */
    private fun readHalTemps(shizuku: ShizukuClient): Map<Int, List<Double>> {
        val now = System.currentTimeMillis()
        if (now - lastHalAt < HAL_CACHE_MS) return lastHal
        val result = mutableMapOf<Int, MutableList<Double>>()
        try {
            val out = shizuku.runShell("dumpsys thermalservice 2>/dev/null")
            Regex("mValue=(-?[0-9.]+),\\s*mType=(\\d+)").findAll(out).forEach { m ->
                val v = m.groupValues[1].toDoubleOrNull() ?: return@forEach
                val type = m.groupValues[2].toIntOrNull() ?: return@forEach
                if (v in 1.0..125.0) result.getOrPut(type) { mutableListOf() }.add(v)
            }
        } catch (_: Throwable) {
        }
        lastHal = result
        lastHalAt = now
        return result
    }

    private fun batteryTempC(): Double? = try {
        val i = context.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val t = i?.getIntExtra("temperature", Int.MIN_VALUE) ?: Int.MIN_VALUE
        if (t != Int.MIN_VALUE && t > 0) t / 10.0 else null
    } catch (_: Throwable) {
        null
    }

    private fun List<Double>.averageOrNull(): Double? = if (isEmpty()) null else average()

    // ------------------------------------------------------------------ RAM

    private fun readFreeRamMb(shizuku: ShizukuClient): Double {
        try {
            val out = shizuku.runShell("cat /proc/meminfo")
            val match = Regex("MemAvailable:\\s+(\\d+)\\s+kB").find(out)
            if (match != null) {
                return match.groupValues[1].toDouble() / 1024.0
            }
        } catch (_: Throwable) {
            // fall through to ActivityManager
        }
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = ActivityManager.MemoryInfo()
            am.getMemoryInfo(info)
            info.availMem / (1024.0 * 1024.0)
        } catch (t: Throwable) {
            -1.0
        }
    }

    // ------------------------------------------------------------------ CPU / GPU usage

    /** Delta-based CPU usage between two /proc/stat samples. First call returns -1. */
    private fun readCpuUsagePercent(shizuku: ShizukuClient): Double {
        return try {
            val out = shizuku.runShell("cat /proc/stat")
            val firstLine = out.lineSequence().firstOrNull { it.startsWith("cpu ") } ?: return -1.0
            val parts = firstLine.trim().split(Regex("\\s+")).drop(1)
            if (parts.size < 4) return -1.0
            val nums = parts.mapNotNull { it.toLongOrNull() }
            if (nums.size < 4) return -1.0
            val idle = (nums.getOrElse(3) { 0L }) + (nums.getOrElse(4) { 0L }) // idle + iowait
            val total = nums.sum()

            if (prevCpuTotal < 0) {
                prevCpuTotal = total; prevCpuIdle = idle
                return -1.0
            }
            val totalDelta = total - prevCpuTotal
            val idleDelta = idle - prevCpuIdle
            prevCpuTotal = total; prevCpuIdle = idle
            if (totalDelta <= 0) return -1.0
            val usage = 100.0 * (1.0 - idleDelta.toDouble() / totalDelta.toDouble())
            usage.coerceIn(0.0, 100.0)
        } catch (t: Throwable) {
            -1.0
        }
    }

    private fun readGpuUsagePercent(shizuku: ShizukuClient): Double {
        // Qualcomm Adreno: "N %" busy
        try {
            val kgsl = shizuku.runShell("cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null")
            val pct = Regex("\\d+").find(kgsl)?.value?.toDoubleOrNull()
            if (pct != null) return pct.coerceIn(0.0, 100.0)
        } catch (_: Throwable) {}

        // Qualcomm: "<busy> <total>" counters
        try {
            val gpubusy = shizuku.runShell("cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null")
            val nums = Regex("\\d+").findAll(gpubusy).map { it.value.toLong() }.toList()
            if (nums.size >= 2 && nums[1] > 0) {
                return (100.0 * nums[0].toDouble() / nums[1].toDouble()).coerceIn(0.0, 100.0)
            }
        } catch (_: Throwable) {}

        // Mali
        try {
            val mali = shizuku.runShell("cat /sys/class/misc/mali0/device/utilization 2>/dev/null")
            val pct = Regex("\\d+").find(mali)?.value?.toDoubleOrNull()
            if (pct != null) return pct.coerceIn(0.0, 100.0)
        } catch (_: Throwable) {}

        return -1.0
    }

    // ------------------------------------------------------------------ storage speed

    /** Sequential-write benchmark of the app cache dir. Returns MB/s. */
    private fun benchmarkStorageSpeed(): Double {
        return try {
            val file = File(context.cacheDir, ".fps_monitor_bench")
            val block = ByteArray(1024 * 1024)
            Random(12345).nextBytes(block)
            val buffer = ByteBuffer.wrap(block)
            val mebibytes = 16
            val start = System.nanoTime()
            FileOutputStream(file).channel.use { ch ->
                repeat(mebibytes) {
                    buffer.clear()
                    while (buffer.hasRemaining()) {
                        ch.write(buffer)
                    }
                }
                ch.force(true)
            }
            val seconds = (System.nanoTime() - start) / 1_000_000_000.0
            file.delete()
            if (seconds <= 0) return -1.0
            val mbps = mebibytes.toDouble() / seconds
            lastStorageSpeedMbps = mbps
            mbps
        } catch (t: Throwable) {
            lastStorageSpeedMbps = -1.0
            -1.0
        }
    }
}
