package com.zsdev.fpsmonitor

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.TextView

/**
 * Draws the floating statistics window in the top-right corner.
 *
 * This is a regular (non-foreground) service: the [MonitorService]
 * foreground service keeps the process alive for the whole session.
 * Started and fed with data by the PlatformChannelHandler / Dart layer.
 */
@SuppressLint("SetTextI18n")
class OverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var fpsText: TextView? = null
    private var tempText: TextView? = null
    private var ramText: TextView? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> showOverlay()
            ACTION_UPDATE -> updateOverlay(intent)
            ACTION_STOP -> stopAndRemove()
        }
        return START_NOT_STICKY
    }

    // ------------------------------------------------------------- window

    private fun showOverlay() {
        if (overlayView != null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !android.provider.Settings.canDrawOverlays(this)) {
            return
        }
        try {
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager
            val view = LayoutInflater.from(this).inflate(R.layout.overlay_stats, null)
            fpsText = view.findViewById(R.id.fps_text)
            tempText = view.findViewById(R.id.temp_text)
            ramText = view.findViewById(R.id.ram_text)

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                x = dp(12)
                y = dp(96)
            }
            wm.addView(view, params)
            windowManager = wm
            overlayView = view
        } catch (t: Throwable) {
            // Never crash the process because of the overlay; monitoring continues in-app.
            t.printStackTrace()
            overlayView = null
            stopSelf()
        }
    }

    private fun updateOverlay(intent: Intent) {
        val fps = intent.getDoubleExtra(EXTRA_FPS, -1.0)
        val cpuTemp = intent.getDoubleExtra(EXTRA_CPU_TEMP, -1.0)
        val gpuTemp = intent.getDoubleExtra(EXTRA_GPU_TEMP, -1.0)
        val freeRam = intent.getDoubleExtra(EXTRA_FREE_RAM, -1.0)

        fpsText?.text = if (fps >= 0) "${fps.toInt()} FPS" else "-- FPS"
        tempText?.text = "CPU ${fmtTemp(cpuTemp)}  GPU ${fmtTemp(gpuTemp)}"
        ramText?.text = if (freeRam >= 0) "RAM ${freeRam.toInt()} MB free" else "RAM -- MB free"

        // Tint FPS green/amber/red by health
        fpsText?.setTextColor(
            when {
                fps < 0 -> 0xFFE5E7EB.toInt()
                fps >= 50 -> 0xFF4ADE80.toInt()
                fps >= 30 -> 0xFFFBBF24.toInt()
                else -> 0xFFF87171.toInt()
            }
        )
    }

    private fun stopAndRemove() {
        try {
            overlayView?.let { windowManager?.removeView(it) }
        } catch (_: Throwable) {
        }
        overlayView = null
        fpsText = null
        tempText = null
        ramText = null
        stopSelf()
    }

    override fun onDestroy() {
        // Best-effort cleanup
        try {
            overlayView?.let { windowManager?.removeView(it) }
        } catch (_: Throwable) {
        }
        overlayView = null
        super.onDestroy()
    }

    // ------------------------------------------------------------- helpers

    private fun fmtTemp(v: Double): String =
        if (v >= 0) "${"%.0f".format(v)}°" else "--°"

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        const val NOTIFICATION_ID = 4101

        const val ACTION_START = "com.zsdev.fpsmonitor.overlay.START"
        const val ACTION_UPDATE = "com.zsdev.fpsmonitor.overlay.UPDATE"
        const val ACTION_STOP = "com.zsdev.fpsmonitor.overlay.STOP"

        const val EXTRA_FPS = "fps"
        const val EXTRA_CPU_TEMP = "cpuTemp"
        const val EXTRA_GPU_TEMP = "gpuTemp"
        const val EXTRA_FREE_RAM = "freeRamMb"

        fun start(context: Context) {
            val intent = Intent(context, OverlayService::class.java).setAction(ACTION_START)
            context.startService(intent)
        }

        fun update(context: Context, fps: Double, cpuTemp: Double, gpuTemp: Double, freeRamMb: Double) {
            val intent = Intent(context, OverlayService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra(EXTRA_FPS, fps)
                .putExtra(EXTRA_CPU_TEMP, cpuTemp)
                .putExtra(EXTRA_GPU_TEMP, gpuTemp)
                .putExtra(EXTRA_FREE_RAM, freeRamMb)
            context.startService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, OverlayService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }
    }
}
