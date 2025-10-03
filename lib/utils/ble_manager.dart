// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/bike_data.dart';

class BLEManager extends ChangeNotifier {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  BluetoothDevice? _connectedDevice;
  
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnected = false;
  BikeData _bikeData = BikeData.blank;
  String _log = "";
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  Timer? _mockDataTimer;
  
  // Channel for native bonding
  static const platform = MethodChannel('com.yezdi.dashboard/bluetooth');

  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _writeChar;

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  List<ScanResult> get scanResults => _scanResults;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  BikeData get bikeData => _bikeData;
  String get logs => _log;

  // These UUIDs may vary - will log all discovered UUIDs
  final Guid _TARGET_SERVICE_UUID = Guid("0000ffe0-0000-1000-8000-00805f9b34fb");
  final Guid _DATA_CHARACTERISTIC_UUID = Guid("0000ffe1-0000-1000-8000-00805f9b34fb");
  final Guid _WRITE_CHARACTERISTIC_UUID = Guid("0000ffe2-0000-1000-8000-00805f9b34fb");

  BLEManager() {
    _startMockDataStream();
    _checkBluetoothState();
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
    _addLog("Logs printed to console");
    print("=== YEZDI DASHBOARD LOGS ===");
    print(_log);
    print("=== END LOGS ===");
  }

  Future<void> _checkBluetoothState() async {
    try {
      if (await FlutterBluePlus.isSupported == false) {
        _addLog("❌ Bluetooth not supported");
        return;
      }
      
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _addLog("⚠️ Bluetooth is OFF - Please turn it ON");
      } else {
        _addLog("✅ Bluetooth is ready");
      }
    } catch (e) {
      _addLog("Bluetooth check error: $e");
    }
  }

  Future<bool> requestPermissions() async {
    _addLog("Requesting permissions...");
    
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    
    if (!allGranted) {
      _addLog("❌ Permissions denied");
      statuses.forEach((permission, status) {
        if (!status.isGranted) {
          _addLog("  - ${permission.toString()}: ${status.toString()}");
        }
      });
      return false;
    }

    bool serviceEnabled = await Permission.location.serviceStatus.isEnabled;
    if (!serviceEnabled) {
      _addLog("❌ Location disabled - Enable in Settings");
      return false;
    }

    _addLog("✅ All permissions granted");
    return true;
  }

  // NEW: Check if device is already bonded
  Future<bool> isDeviceBonded(BluetoothDevice device) async {
    try {
      final List<BluetoothDevice> bondedDevices = await FlutterBluePlus.bondedDevices;
      return bondedDevices.any((d) => d.remoteId == device.remoteId);
    } catch (e) {
      _addLog("Error checking bonded devices: $e");
      return false;
    }
  }

  // NEW: Trigger bonding using platform channel
  Future<bool> createBond(BluetoothDevice device) async {
    try {
      _addLog("🔐 Initiating pairing with ${device.platformName}...");
      _addLog("📱 Check bike display for PIN code!");
      
      // Use platform channel to call native createBond
      final bool result = await platform.invokeMethod('createBond', {
        'address': device.remoteId.toString()
      });
      
      if (result) {
        _addLog("✅ Device paired successfully!");
        return true;
      } else {
        _addLog("❌ Pairing failed or cancelled");
        return false;
      }
    } catch (e) {
      _addLog("❌ Bonding error: $e");
      return false;
    }
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    bool hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      _addLog("❌ Cannot scan: Missing permissions");
      return;
    }

    _addLog("🔍 Starting BLE Scan (nRF style - all devices)...");
    _isScanning = true;
    _scanResults.clear();
    notifyListeners();

    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (!_scanResults.any((sr) => sr.device.remoteId == r.device.remoteId)) {
            // ✅ SHOW ALL DEVICES - like nRF Connect
            String deviceName = r.device.platformName.isNotEmpty 
                ? r.device.platformName 
                : r.advertisementData.localName.isNotEmpty
                    ? r.advertisementData.localName
                    : "Unknown Device";
            
            _scanResults.add(r);
            _addLog("📱 Found: $deviceName");
            _addLog("   MAC: ${r.device.remoteId}");
            _addLog("   RSSI: ${r.rssi} dBm");
            
            // Log advertised services
            if (r.advertisementData.serviceUuids.isNotEmpty) {
              _addLog("   Services: ${r.advertisementData.serviceUuids.map((u) => u.toString().substring(4, 8)).join(', ')}");
            }
          }
        }
        notifyListeners();
      }, onError: (e) => _addLog("❌ Scan Error: $e"));

      // Start scan WITHOUT filters (shows all devices like nRF)
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
        // NO withServices filter - this is key!
      );
      
      Future.delayed(const Duration(seconds: 15), stopScan);
    } catch (e) {
      _addLog("❌ Scan failed: $e");
      _isScanning = false;
      notifyListeners();
    }
  }

  void stopScan() {
    if (!_isScanning) return;
    _addLog("⏹️ Scan stopped. Found ${_scanResults.length} devices");
    _isScanning = false;
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    notifyListeners();
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnected) await disconnectFromDevice();
    
    String deviceName = device.platformName.isEmpty ? "Unknown Device" : device.platformName;
    _addLog("🔌 Connecting to $deviceName (${device.remoteId})");
    stopScan();

    // Check if device is bonded
    bool isBonded = await isDeviceBonded(device);
    _addLog(isBonded ? "✅ Device already paired" : "⚠️ Device not paired yet");

    _connectionStateSubscription = device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.disconnected) {
        _isConnected = false;
        _connectedDevice = null;
        _bikeData = BikeData.blank;
        _dataChar = null;
        _writeChar = null;
        _addLog("❌ Disconnected from device");
        notifyListeners();
        _startReconnect(device);
      } else if (state == BluetoothConnectionState.connected) {
        _isConnected = true;
        _connectedDevice = device;
        _reconnectTimer?.cancel();
        _reconnectAttempt = 0;
        _addLog("✅ Connected! Discovering services...");
        await _discoverAndSubscribe(device);
        notifyListeners();
      }
    });

    try {
      await device.connect(
        timeout: const Duration(seconds: 20),
        autoConnect: false,
      );
    } catch (e) {
      String errorMsg = e.toString();
      _addLog("❌ Connection failed: $errorMsg");
      
      // Handle specific errors
      if (errorMsg.contains("133")) {
        _addLog("⚠️ Error 133 detected - Device needs pairing");
        _addLog("📱 Attempting to pair...");
        
        // Trigger bonding
        bool bonded = await createBond(device);
        if (bonded) {
          _addLog("🔄 Retrying connection after pairing...");
          await Future.delayed(Duration(seconds: 2));
          await device.connect(timeout: const Duration(seconds: 20));
        }
      } else if (errorMsg.contains("already_connected")) {
        _addLog("ℹ️ Already connected, proceeding...");
        await _discoverAndSubscribe(device);
      } else {
        _connectionStateSubscription?.cancel();
      }
    }
  }
  
  void _startReconnect(BluetoothDevice device) {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    int delaySeconds = pow(2, min(_reconnectAttempt, 4)).toInt();
    _addLog("🔄 Reconnecting in ${delaySeconds}s (Attempt ${_reconnectAttempt + 1})");
    
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
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
    _addLog("🔌 Manual disconnect");
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      _addLog("📋 Found ${services.length} services");
      
      bool foundTargetService = false;
      
      for (var service in services) {
        String serviceUuid = service.uuid.toString().toUpperCase();
        _addLog("🔷 Service: ${serviceUuid.substring(4, 8)}");
        
        if (service.uuid == _TARGET_SERVICE_UUID) {
          foundTargetService = true;
          _addLog("   ✅ Target service FFE0 found!");
        }
        
        for (var char in service.characteristics) {
          final props = char.properties;
          String charUuid = char.uuid.toString().substring(4, 8).toUpperCase();
          _addLog("   📝 Char $charUuid: R:${props.read} W:${props.write} N:${props.notify}");
          
          // Find data characteristic
          if (char.uuid == _DATA_CHARACTERISTIC_UUID || 
              (!foundTargetService && props.notify)) {
            _dataChar = char;
            _addLog("      ✅ DATA characteristic");
          }
          
          // Find write characteristic
          if (char.uuid == _WRITE_CHARACTERISTIC_UUID || 
              (!foundTargetService && props.write)) {
            _writeChar = char;
            _addLog("      ✅ WRITE characteristic");
          }
        }
      }
      
      if (!foundTargetService) {
        _addLog("⚠️ Target service FFE0 not found");
        _addLog("💡 Check logs above for actual service UUIDs");
      }

      // Try initial read
      if (_dataChar != null && _dataChar!.properties.read) {
        try {
          final initialData = await _dataChar!.read();
          _addLog("📥 Initial data: ${_bytesToHex(initialData)}");
        } catch (e) {
          if (e.toString().contains("133") || e.toString().contains("authentication")) {
            _addLog("🔐 Read requires pairing - triggering bond...");
            await createBond(device);
          } else {
            _addLog("⚠️ Read error: $e");
          }
        }
      }

      // Subscribe to notifications
      if (_dataChar != null) {
        if (_dataChar!.properties.notify || _dataChar!.properties.indicate) {
          try {
            await _dataChar!.setNotifyValue(true);
            _dataChar!.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                _addLog("📊 Data: ${_bytesToHex(value)}");
                _parseBikeData(value);
              }
            });
            _addLog("✅ Subscribed to notifications");
          } catch (e) {
            if (e.toString().contains("133") || e.toString().contains("authentication")) {
              _addLog("🔐 Subscribe requires pairing");
              await createBond(device);
            } else {
              _addLog("❌ Subscribe error: $e");
            }
          }
        } else {
          _addLog("❌ NOTIFY not supported");
        }
      }

    } catch (e) {
      _addLog("❌ Discovery error: $e");
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  void _parseBikeData(List<int> data) {
    if (data.length < 4) {
      _addLog("⚠️ Data too short: ${data.length} bytes");
      return;
    }

    try {
      _bikeData = BikeData(
        speed: data.length > 0 ? data[0] : 0,
        rpm: data.length > 1 ? data[1] * 50 : 0,
        gear: data.length > 2 ? (data[2] & 0x0F) : 0,
        fuel: data.length > 3 ? data[3] / 255.0 : 0.0,
        mode: data.length > 2 ? _parseMode((data[2] & 0xF0) >> 4) : 'ROAD',
        highBeam: data.length > 4 ? (data[4] & 0x01) != 0 : false,
        hazard: data.length > 4 ? (data[4] & 0x02) != 0 : false,
        engineCheck: data.length > 4 ? (data[4] & 0x04) != 0 : false,
        batteryWarning: data.length > 4 ? (data[4] & 0x08) != 0 : false,
      );
      notifyListeners();
    } catch (e) {
      _addLog("❌ Parse error: $e");
    }
  }

  String _parseMode(int modeValue) {
    switch (modeValue) {
      case 0: return 'ROAD';
      case 1: return 'RAIN';
      case 2: return 'OFFROAD';
      default: return 'UNKNOWN';
    }
  }

  Future<void> sendCommand(List<int> command) async {
    if (_writeChar == null) {
      _addLog("❌ Write characteristic not available");
      return;
    }
    
    try {
      await _writeChar!.write(command, withoutResponse: true);
      _addLog("📤 Sent: ${_bytesToHex(command)}");
    } catch (e) {
      _addLog("❌ Write error: $e");
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
          odo: 12345.6 + random.nextDouble() * 10,
          tripA: 123.4 + random.nextDouble(),
          tripB: 56.7 + random.nextDouble(),
          dte: 150.0 - random.nextInt(50),
          afeA: 25.5 + random.nextDouble() * 5,
          afeB: 28.1 + random.nextDouble() * 5,
        );
        notifyListeners();
      }
    });
  }
}
