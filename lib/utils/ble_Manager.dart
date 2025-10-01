// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/bike_data.dart';

class BLEManager extends ChangeNotifier {
  final FlutterBluePlus _flutterBlue = FlutterBluePlus.instance;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothDeviceState>? _connectionStateSubscription;
  BluetoothDevice? _connectedDevice;
  
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnected = false;
  BikeData _bikeData = BikeData.blank;
  String _log = "";
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  Timer? _mockDataTimer;

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  List<ScanResult> get scanResults => _scanResults;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  BikeData get bikeData => _bikeData;
  String get logs => _log;

  // --- CORRECT UUIDs FROM YOUR SCREENSHOT ---
  // Yeh UUIDs aapke nRF Connect ke screenshot se daale gaye hain.
  final Guid _TARGET_SERVICE_UUID = Guid("0000ffe0-0000-1000-8000-00805f9b34fb");
  final Guid _DATA_CHARACTERISTIC_UUID = Guid("0000ffe1-0000-1000-8000-00805f9b34fb");
  final Guid _WRITE_CHARACTERISTIC_UUID = Guid("0000ffe2-0000-1000-8000-00805f9b34fb");

  BLEManager() {
    _startMockDataStream();
  }

  @override
  void dispose() {
    _mockDataTimer?.cancel();
    _reconnectTimer?.cancel();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    super.dispose();
  }

  void _addLog(String message) {
    print(message);
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    _log = "$_log[$timestamp] $message\n";
    notifyListeners();
  }
  
  Future<void> exportLogs() async {
    try {
      final bytes = utf8.encode(_log);
      await FilePicker.platform.saveFile(
          dialogTitle: 'Save BLE Logs',
          fileName: 'yezdi_dashboard_ble_logs.txt',
          bytes: bytes,
      );
      _addLog("Log export process initiated.");
    } catch (e) {
      _addLog("Error exporting logs: $e");
    }
  }

  void startScan() {
    if (_isScanning) return;
    _addLog("Starting BLE Scan...");
    _isScanning = true;
    _scanResults.clear();
    notifyListeners();

    _scanSubscription = _flutterBlue.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (!_scanResults.any((sr) => sr.device.id == r.device.id)) {
           if(r.device.name.isNotEmpty) _scanResults.add(r);
        }
      }
      notifyListeners();
    }, onError: (e) => _addLog("Scan Error: $e"));

    _flutterBlue.startScan(timeout: const Duration(seconds: 10));
    Future.delayed(const Duration(seconds: 10), stopScan);
  }

  void stopScan() {
    _addLog("Stopping BLE Scan.");
    _isScanning = false;
    _flutterBlue.stopScan();
    _scanSubscription?.cancel();
    notifyListeners();
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnected) await disconnectFromDevice();
    _addLog("Attempting to connect to ${device.name} (${device.id})");
    stopScan();

    _connectionStateSubscription = device.state.listen((state) async {
      if (state == BluetoothDeviceState.disconnected) {
        _isConnected = false;
        _connectedDevice = null;
        _bikeData = BikeData.blank;
        _addLog("Device disconnected.");
        notifyListeners();
        _startReconnect(device);
      } else if (state == BluetoothDeviceState.connected) {
        _isConnected = true;
        _connectedDevice = device;
        _reconnectTimer?.cancel();
        _reconnectAttempt = 0;
        _addLog("Device connection successful. Discovering services...");
        await _discoverServicesAndAuthenticate(device);
        notifyListeners();
      }
    });

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    } catch (e) {
      _addLog("Connection Error: $e");
      _connectionStateSubscription?.cancel();
    }
  }
  
  void _startReconnect(BluetoothDevice device) {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    int delaySeconds = pow(2, min(_reconnectAttempt, 4)).toInt(); // Max 16 seconds
    _addLog("Will attempt to reconnect in $delaySeconds seconds...");
    
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
        _addLog("Reconnecting... (Attempt ${_reconnectAttempt + 1})");
        connectToDevice(device);
    });
    _reconnectAttempt++;
  }

  Future<void> disconnectFromDevice() async {
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _addLog("Manual disconnection.");
  }

  Future<void> _discoverServicesAndAuthenticate(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      _addLog("Found ${services.length} services.");
      for (var service in services) {
        _addLog("Service: ${service.uuid}");
        for (var char in service.characteristics) {
          _addLog("  - Char: ${char.uuid} | Props: ${char.properties}");
        }
      }
      
      bool authenticated = await _authAttempt_GenericKey(device) || await _authAttempt_Bonding(device);

      if (authenticated) {
        _addLog("Authentication successful. Subscribing to data...");
        await _subscribeToDataCharacteristic(device);
      } else {
        _addLog("All authentication methods failed.");
        disconnectFromDevice();
      }
    } catch (e) {
      _addLog("Service Discovery/Auth Error: $e");
    }
  }
  
  Future<bool> _authAttempt_GenericKey(BluetoothDevice device) async {
    _addLog("Auth Attempt 1: Writing generic key...");
    try {
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid == _TARGET_SERVICE_UUID) {
          for (var char in service.characteristics) {
            if (char.uuid == _WRITE_CHARACTERISTIC_UUID && char.properties.write) {
              _addLog("Found target write characteristic. Writing default key...");
              await char.write(utf8.encode('YEZDI_AUTH_DEFAULT'), withoutResponse: true);
              _addLog("Wrote generic key to ${char.uuid}. Assuming success.");
              return true;
            }
          }
        }
      }
      _addLog("Target write characteristic not found.");
      return false;
    } catch (e) {
      _addLog("Generic Key Write failed: $e");
      return false;
    }
  }

  Future<bool> _authAttempt_Bonding(BluetoothDevice device) async {
    _addLog("Auth Attempt 2: Requesting bonding...");
    try {
      await device.pair();
      _addLog("Bonding request successful.");
      return true;
    } catch (e) {
      _addLog("Bonding failed: $e");
      return false;
    }
  }

  Future<void> _subscribeToDataCharacteristic(BluetoothDevice device) async {
    try {
        List<BluetoothService> services = await device.discoverServices();
        for (var service in services) {
            if(service.uuid == _TARGET_SERVICE_UUID){
                for (BluetoothCharacteristic c in service.characteristics) {
                    if (c.uuid == _DATA_CHARACTERISTIC_UUID && c.properties.notify) {
                        await c.setNotifyValue(true);
                        c.value.listen((value) {
                            if (value.isNotEmpty) _parseBikeData(value);
                        });
                        _addLog("Successfully subscribed to notifications on ${c.uuid}.");
                        return; // Exit after successful subscription
                    }
                }
            }
        }
        _addLog("Could not find the target data characteristic to subscribe.");
    } catch (e) {
        _addLog("Subscription Error: $e");
    }
  }

  void _parseBikeData(List<int> data) {
    _addLog("Data Received: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}");
    // This is a placeholder. You must reverse-engineer your bike's protocol.
    try {
      _bikeData = BikeData(
        speed: data.length > 0 ? data[0] : 0,
        rpm: data.length > 1 ? data[1] * 100 : 0,
        gear: data.length > 2 ? data[2] : 0,
        fuel: data.length > 3 ? data[3] / 100.0 : 0.0,
      );
      notifyListeners();
    } catch (e) {
      _addLog("Data parsing error: $e");
    }
  }

  void _startMockDataStream() {
    _mockDataTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isConnected) {
        final random = Random();
        _bikeData = BikeData(
          speed: random.nextInt(181),
          rpm: random.nextInt(8001),
          gear: random.nextInt(7),
          fuel: random.nextDouble(),
          mode: ['ROAD', 'RAIN', 'OFFROAD'][random.nextInt(3)],
          highBeam: random.nextBool(),
          hazard: random.nextBool(),
          engineCheck: random.nextBool(),
          batteryWarning: random.nextBool(),
          odo: 12345.6, tripA: 123.4, tripB: 56.7, dte: 150.0, afeA: 25.5, afeB: 28.1,
        );
        notifyListeners();
      }
    });
  }
}
