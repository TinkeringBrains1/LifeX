package com.example.lifex 

import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.lifex/ble_radio"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBeacon" -> {
                    startBleService()
                    result.success("BLE signal emission activated")
                }
                "stopBeacon" -> {
                    stopBleService()
                    result.success("Signal deactivated.")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startBleService() {
        val serviceIntent = Intent(this, BleBeaconService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Android 8.0+ requires this specific command for background tasks
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopBleService() {
        val serviceIntent = Intent(this, BleBeaconService::class.java)
        stopService(serviceIntent)
    }
}