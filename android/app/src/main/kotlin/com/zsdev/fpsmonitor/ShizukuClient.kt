package com.zsdev.fpsmonitor

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import android.util.Log
import rikka.shizuku.Shizuku
import java.util.concurrent.TimeUnit

/**
 * Thin wrapper around the Shizuku binder.
 *
 * Lifecycle:
 *  1. [status] polls whether the Shizuku manager is running and whether this
 *     app already holds the Shizuku permission.
 *  2. [bind] requests the permission (shows the Shizuku dialog once) and/or
 *     binds the [UserService] that executes shell commands with shell uid.
 *  3. [runShell] executes a command through the privileged user service when
 *     bound; falls back to the app's own process for unprivileged files
 *     (e.g. /proc/meminfo, /sys thermal zones when world-readable).
 */
class ShizukuClient(private val context: Context) {

    @Volatile
    private var userService: IUserService? = null

    private var bindRequested = false

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { _, grantResult ->
            Log.i(TAG, "Shizuku permission result: $grantResult")
            if (grantResult == PackageManager.PERMISSION_GRANTED) {
                bindUserService()
            }
        }

    init {
        try {
            Shizuku.addRequestPermissionResultListener(permissionListener)
        } catch (t: Throwable) {
            Log.w(TAG, "addRequestPermissionResultListener failed: ${t.message}")
        }
    }

    fun ping(): Boolean = try {
        Shizuku.pingBinder()
    } catch (t: Throwable) {
        false
    }

    fun version(): Int = if (ping()) {
        try {
            Shizuku.getVersion()
        } catch (t: Throwable) {
            -1
        }
    } else {
        -1
    }

    fun hasPermission(): Boolean = try {
        ping() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (t: Throwable) {
        false
    }

    fun isPreV11(): Boolean = try {
        ping() && Shizuku.isPreV11()
    } catch (t: Throwable) {
        false
    }

    fun isBound(): Boolean = userService != null

    fun status(): Map<String, Any> = mapOf(
        "ping" to ping(),
        "version" to version(),
        "permission" to if (hasPermission()) 0 else -1,
        "bound" to isBound(),
        "preV11" to isPreV11()
    )

    /** Request the Shizuku permission (if needed) and bind the user service. */
    fun bind() {
        if (!ping()) {
            Log.w(TAG, "Shizuku is not running — start it via ADB/root first")
            return
        }
        if (!hasPermission()) {
            bindRequested = true
            try {
                Shizuku.requestPermission(REQUEST_PERMISSION_CODE)
            } catch (t: Throwable) {
                Log.e(TAG, "requestPermission failed: ${t.message}")
            }
            return
        }
        bindUserService()
    }

    private fun bindUserService() {
        if (userService != null) {
            Log.i(TAG, "User service already bound")
            return
        }
        try {
            val args = Shizuku.UserServiceArgs(
                ComponentName(context.packageName, UserService::class.java.name)
            )
                .tag(USER_SERVICE_TAG)
                .daemon(false)
                .processNameSuffix("user_service")
                .debuggable(false)
                .version(USER_SERVICE_VERSION)

            Shizuku.bindUserService(args, object : ServiceConnection {
                override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                    userService = service?.let { IUserService.Stub.asInterface(it) }
                    Log.i(TAG, "User service connected: bound=${userService != null}")
                }

                override fun onServiceDisconnected(name: ComponentName?) {
                    Log.w(TAG, "User service disconnected")
                    userService = null
                }
            })
        } catch (t: Throwable) {
            Log.e(TAG, "bindUserService failed: ${t.message}")
        }
    }

    fun unbind() {
        val svc = userService ?: return
        try {
            val args = Shizuku.UserServiceArgs(
                ComponentName(context.packageName, UserService::class.java.name)
            )
                .tag(USER_SERVICE_TAG)
                .daemon(false)
                .processNameSuffix("user_service")
                .version(USER_SERVICE_VERSION)
            Shizuku.unbindUserService(args, null, true)
        } catch (t: Throwable) {
            Log.w(TAG, "unbindUserService failed: ${t.message}")
        } finally {
            userService = null
        }
    }

    /**
     * Run a shell command. Prefers the privileged Shizuku user service;
     * falls back to the app process for world-readable files so the UI can
     * still show something on devices where Shizuku is unavailable.
     */
    fun runShell(command: String): String {
        val svc = userService
        if (svc != null) {
            return try {
                svc.exec(command)
            } catch (t: Throwable) {
                "ERR: ${t.message}"
            }
        }
        return try {
            val process = ProcessBuilder("sh", "-c", command)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            if (!process.waitFor(SHELL_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                process.destroy()
                "ERR: timeout"
            } else {
                output
            }
        } catch (t: Throwable) {
            "ERR: ${t.message}"
        }
    }

    companion object {
        private const val TAG = "FpsShizukuClient"
        private const val REQUEST_PERMISSION_CODE = 4201
        private const val USER_SERVICE_TAG = "fps_monitor_user_service"
        private const val USER_SERVICE_VERSION = 1
        private const val SHELL_TIMEOUT_SECONDS = 6L
    }
}
