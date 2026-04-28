package com.example.lifex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter 
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver 
import android.content.Context
import android.content.Intent
import android.content.IntentFilter 
import android.os.Build
import android.os.IBinder
import android.os.ParcelUuid
import androidx.core.app.NotificationCompat
import java.util.UUID

class BleBeaconService : Service() {

    private var advertiser: BluetoothLeAdvertiser? = null
    private val channelId = "LifeX_Emergency_Channel"
    private val lifeXUuid = ParcelUuid(UUID.fromString("8b0caaf2-1718-4503-9e46-1db98db18218"))

    // The Kill Switch: Destroys everything if physical Bluetooth is turned off
    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                if (state == BluetoothAdapter.STATE_OFF || state == BluetoothAdapter.STATE_TURNING_OFF) {
                    println("LifeX: Bluetooth physically turned off. Auto-killing service.")
                    stopSelf() 
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        registerReceiver(bluetoothStateReceiver, filter)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 1. THE TRIPWIRE: Did the user just try to swipe the notification away?
        if (intent?.action == "ACTION_DISMISSED") {
            println("LifeX: User attempted to swipe notification. Respawning!")
            showPersistentNotification()
            return START_STICKY
        }

        // 2. Normal Startup
        showPersistentNotification()
        startAdvertising()

        return START_STICKY 
    }

    // Extracted the notification logic into its own function so we can loop it
    private fun showPersistentNotification() {
        // Intent to open the app when tapped
        val notificationIntent = Intent(this, MainActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, pendingIntentFlags
        )

        // NEW: Intent to trigger the Respawn Loop when swiped
        val dismissIntent = Intent(this, BleBeaconService::class.java).apply {
            action = "ACTION_DISMISSED"
        }
        val dismissPendingIntent = PendingIntent.getService(
            this, 1, dismissIntent, pendingIntentFlags
        )

        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("LifeX Emergency Mode")
            .setContentText("Broadcasting BLE Survival Beacon... Tap to open.")
            .setSmallIcon(android.R.drawable.ic_dialog_alert) 
            .setOngoing(true) 
            .setContentIntent(pendingIntent) // Handles Taps
            .setDeleteIntent(dismissPendingIntent) // Handles Swipes (The Trap)
            .build()

        startForeground(1, notification)
    }

    private fun startAdvertising() {
        if (advertiser != null) return // Prevent double-starting if respawning

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter
        advertiser = adapter.bluetoothLeAdvertiser

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(lifeXUuid)
            .build()

        advertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
        }
        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
        }
    }

    override fun onDestroy() {
        unregisterReceiver(bluetoothStateReceiver)
        advertiser?.stopAdvertising(advertiseCallback)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null 

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "LifeX Emergency Beacon", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Keeps the survival radio alive." }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}