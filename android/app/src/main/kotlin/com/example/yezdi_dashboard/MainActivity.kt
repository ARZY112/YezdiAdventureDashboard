package com.yezdi.dashboard

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.yezdi.dashboard/bluetooth"
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "createBond") {
                val address = call.argument<String>("address")
                if (address != null) {
                    val bonded = createBond(address)
                    result.success(bonded)
                } else {
                    result.error("INVALID_ARGUMENT", "Device address is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
    
    private fun createBond(address: String): Boolean {
        return try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            val device: BluetoothDevice = bluetoothAdapter.getRemoteDevice(address)
            device.createBond()
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
