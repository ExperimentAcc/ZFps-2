package com.zsdev.fpsmonitor

import android.content.Context
import android.util.Log

/**
 * Shizuku user service. Instantiated by the Shizuku server inside a
 * privileged process (shell uid, or root if Shizuku runs in root mode).
 *
 * IMPORTANT: this class must keep a public no-argument constructor and must
 * not reference app resources or the app's classes beyond the AIDL stub,
 * because it is loaded by `app_process` from the Shizuku server.
 */
class UserService : IUserService.Stub {

    constructor() {
        Log.i(TAG, "constructor")
    }

    /** Shizuku API v13+ may pass a Context created via createPackageContextAsUser. */
    constructor(context: Context) {
        Log.i(TAG, "constructor with Context: $context")
    }

    override fun destroy() {
        Log.i(TAG, "destroy()")
        System.exit(0)
    }

    override fun exec(command: String): String {
        return try {
            val process = ProcessBuilder("sh", "-c", command)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            process.waitFor()
            output
        } catch (e: Exception) {
            "ERR: ${e.message}"
        }
    }

    companion object {
        private const val TAG = "FpsUserService"
    }
}
