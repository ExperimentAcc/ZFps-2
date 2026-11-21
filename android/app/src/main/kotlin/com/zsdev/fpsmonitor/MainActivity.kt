package com.zsdev.fpsmonitor

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private lateinit var channelHandler: PlatformChannelHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channelHandler = PlatformChannelHandler(
            this,
            flutterEngine.dartExecutor.binaryMessenger
        )
        channelHandler.register()
    }
}
