package com.zsdev.fpsmonitor

import android.util.Log

/**
 * Reads real per-frame presentation timestamps of the game's SurfaceFlinger
 * layer (`dumpsys SurfaceFlinger --latency`) and turns them into frame times.
 *
 * Every call returns only frames that are NEW since the previous call, so the
 * caller can accumulate an exact frame-time series (needed for 1% / 0.1% lows).
 * Not thread-safe: use from a single thread.
 */
class FrameSampler {

    class Batch(
        /** Time between consecutive presented frames, in milliseconds. */
        val frameTimesMs: List<Double>,
        /** False when no frame data could be read (layer not found, no Shizuku...). */
        val valid: Boolean
    )

    private var packageName: String? = null
    private var layer: String? = null
    private var lastAttemptAt = 0L
    private var lastPresentNs = 0L
    private var lastFreshAt = 0L

    private fun resetState() {
        layer = null
        lastAttemptAt = 0L
        lastPresentNs = 0L
        lastFreshAt = 0L
    }

    fun poll(rawPackage: String, shizuku: ShizukuClient, reset: Boolean): Batch {
        val pkg = rawPackage.replace(Regex("[^A-Za-z0-9_.]"), "")
        if (pkg.isEmpty()) return MISS
        if (reset || pkg != packageName) {
            resetState()
            packageName = pkg
        }

        val now = System.currentTimeMillis()

        if (layer == null) {
            // Don't hammer dumpsys while the game has not started yet
            if (now - lastAttemptAt < RETRY_MS) return MISS
            lastAttemptAt = now
            val found = resolveLayer(pkg, shizuku) ?: return MISS
            layer = found
            lastPresentNs = 0L
            lastFreshAt = now
            Log.i(TAG, "Frame layer: $found")
        }

        val name = layer ?: return MISS
        val times = readPresentTimes(name, shizuku)
        if (times.isEmpty()) {
            layer = null
            return MISS
        }

        // Layer was recreated (timestamps jumped backwards)
        if (times.last() < lastPresentNs) lastPresentNs = 0L

        val fresh = times.filter { it > lastPresentNs }
        if (fresh.isEmpty()) {
            // Valid layer but nothing new: paused / static screen. If it stays
            // like this for a while the layer is probably dead, so look again.
            if (now - lastFreshAt > STALE_MS) layer = null
            return Batch(emptyList(), true)
        }
        lastFreshAt = now

        val deltas = ArrayList<Double>(fresh.size)
        var prev = lastPresentNs
        for (t in fresh) {
            if (prev > 0L) {
                val ms = (t - prev) / 1_000_000.0
                // Ignore gaps > 1 s (loading screens, pauses); they are not "frames"
                if (ms > 0.0 && ms <= MAX_FRAME_MS) deltas.add(ms)
            }
            prev = t
        }
        lastPresentNs = fresh.last()
        return Batch(deltas, true)
    }

    // ---------------------------------------------------------------- helpers

    /** Picks the layer that is actually rendering the game. */
    private fun resolveLayer(pkg: String, shizuku: ShizukuClient): String? {
        val out = shizuku.runShell("dumpsys SurfaceFlinger --list 2>/dev/null | grep -F '$pkg'")
        if (out.isBlank() || out.startsWith("ERR")) return null

        val candidates = out.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !IGNORED_LAYER.containsMatchIn(it) }
            .distinct()
            .toList()
        if (candidates.isEmpty()) return null

        // Games render into a SurfaceView, so test those first
        val ordered = candidates.sortedBy { if (it.startsWith("SurfaceView")) 0 else 1 }.take(6)

        var best: String? = null
        var bestIsSurface = false
        var bestCount = -1
        var bestLast = 0L
        for (c in ordered) {
            val times = readPresentTimes(c, shizuku)
            if (times.size < 2) continue
            val isSurface = c.startsWith("SurfaceView")
            val better = when {
                best == null -> true
                isSurface != bestIsSurface -> isSurface
                times.size != bestCount -> times.size > bestCount
                else -> times.last() > bestLast
            }
            if (better) {
                best = c
                bestIsSurface = isSurface
                bestCount = times.size
                bestLast = times.last()
            }
        }
        return best
    }

    /**
     * Output format of `--latency <layer>`: first line is the refresh period,
     * then up to 127 lines of "desiredPresent actualPresent frameReady" (ns).
     * We use the actual present time. Pending frames show Long.MAX_VALUE.
     */
    private fun readPresentTimes(layerName: String, shizuku: ShizukuClient): List<Long> {
        val quoted = "'" + layerName.replace("'", "'\\''") + "'"
        val out = shizuku.runShell("dumpsys SurfaceFlinger --latency $quoted 2>/dev/null")
        if (out.isBlank() || out.startsWith("ERR")) return emptyList()

        val times = ArrayList<Long>(128)
        var first = true
        for (line in out.lineSequence()) {
            if (first) {
                first = false
                continue
            }
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size < 3) continue
            val t = parts[1].toLongOrNull() ?: continue
            if (t <= 0L || t >= INVALID_NS) continue
            times.add(t)
        }
        times.sort()
        return times
    }

    companion object {
        private const val TAG = "FpsFrames"
        private const val RETRY_MS = 2000L
        private const val STALE_MS = 5000L
        private const val MAX_FRAME_MS = 1000.0
        private const val INVALID_NS = 9_000_000_000_000_000_000L

        private val IGNORED_LAYER =
            Regex("Background for|Bounds for|Splash Screen|Letterbox|Dim layer")

        val MISS = Batch(emptyList(), false)
    }
}
