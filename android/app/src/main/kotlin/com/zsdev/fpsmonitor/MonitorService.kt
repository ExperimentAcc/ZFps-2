package com.zsdev.fpsmonitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Foreground service that owns an active monitoring session.
 *
 * Its sole jobs are to keep the process alive (with a wake lock) while the
 * game is in the foreground and to host the persistent "session active"
 * notification. Metric collection is driven from the Dart layer via the
 * platform channel and the overlay is handled by [OverlayService].
 */
class MonitorService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val appName = intent.getStringExtra(EXTRA_APP_NAME) ?: "App"
                startInForeground(appName)
                acquireWakeLock()
                // Bring up the floating overlay window
                OverlayService.start(applicationContext)
            }
            ACTION_STOP -> {
                OverlayService.stop(applicationContext)
                releaseWakeLock()
                stopForegroundCompat()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    // ------------------------------------------------------------- lifecycle

    private fun startInForeground(appName: String) {
        val notification: Notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_fps)
            .setContentTitle("FPS Monitor")
            .setContentText("Monitoring $appName — overlay is live")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setPriority(Notification.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                512 // ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE (API 34)
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "fpsmonitor:session").apply {
                setReferenceCounted(false)
            }
        }
        try {
            wakeLock?.acquire(4 * 60 * 60 * 1000L) // safety timeout: 4 hours
        } catch (_: Throwable) {
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Throwable) {
        }
        wakeLock = null
    }

    // ------------------------------------------------------------- channel

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Monitoring session",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent notification shown while a session is running"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val CHANNEL_ID = "fps_monitor_session"
        private const val NOTIFICATION_ID = 4102

        const val ACTION_START = "com.zsdev.fpsmonitor.monitor.START"
        const val ACTION_STOP = "com.zsdev.fpsmonitor.monitor.STOP"
        const val EXTRA_APP_NAME = "app_name"

        fun start(context: Context, appName: String) {
            val intent = Intent(context, MonitorService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_APP_NAME, appName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, MonitorService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }
    }
}
