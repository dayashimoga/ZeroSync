package org.zerosync.airdrop_qr

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "org.zerosync/security_window_guard"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureScreen" -> {
                    activity?.runOnUiThread {
                        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "disableSecureScreen" -> {
                    activity?.runOnUiThread {
                        activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "isSecureScreenEnabled" -> {
                    val flags = activity?.window?.attributes?.flags ?: 0
                    val isSecure = (flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                    result.success(isSecure)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
