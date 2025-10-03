// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
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

  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _writeChar;

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  List<ScanResult> get scanResults => _scanResults;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  BikeData get bikeData => _bikeData;
  String get logs => _log;

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
  
  Future<void> _checkBluetoothState() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      _addLog("Bluetooth adapter state: $adapterState");
      
      if (adapterState != BluetoothAdapterState.on) {
        _addLog("WARNING: Bluetooth is OFF. Please turn it on.");
      }
    } catch (e) {
      _addLog("Error checking Bluetooth state: $e");
    }
  }

  Future<void> exportLogs() async {
    _addLog("Logs printed to console");
    print("=== YEZDI DASHBOARD LOGS ===");
    print(_log);
    print("=== END LOGS ===");
  }

  Future<void> startScan() async {
    if (_isScanning) return;
    
    // Check permissions first
    final permissionsGranted = await _checkPermissions();
    if (!permissionsGranted) {
      _addLog("ERROR: Permissions not granted!");
      return;
    }

    // Check if Bluetooth is on
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _addLog("ERROR: Bluetooth is OFF. Please turn it on in settings.");
      return;
    }

    _addLog("Starting BLE scan...");
    _isScanning = true;
    _scanResults.clear();
    notifyListeners();

    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        _addLog("Scan results received: ${results.length} devices");
        for (ScanResult r in results) {
          if (!_scanResults.any((sr) => sr.device.remoteId == r.device.remoteId)) {
            _scanResults.add(r);
            final name = r.device.platformName.isEmpty ? "Unknown Device" : r.device.platformName;
            _addLog("Found device: $name (${r.device.remoteId})");
          }
        }
        notifyListeners();
      }, onError: (e) {
        _addLog("Scan error: $e");
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
      
      _addLog("Scan started successfully");
      Future.delayed(const Duration(seconds: 15), stopScan);
    } catch (e) {
      _addLog("Failed to start scan: $e");
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<bool> _checkPermissions() async {
    _addLog("Checking permissions...");
    
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    
    if (!allGranted) {
      _addLog("Permissions denied:");
      statuses.forEach((permission, status) {
        if (!status.isGranted) {
          _addLog("  - ${permission.toString()}: ${status.toString()}");
        }
      });
    } else {
      _addLog("All permissions granted");
    }

    return allGranted;
  }

  void stopScan() {
    if (!_isScanning) return;
    _addLog("Stopping scan. Found ${_scanResults.length} devices total.");
    _isScanning = false;
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    notifyListeners();
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnected) await disconnectFromDevice();
    
    final name = device.platformName.isEmpty ? "Unknown" : device.platformName;
    _addLog("Connecting to $name (${device.remoteId})");
    stopScan();

    _connectionStateSubscription = device.connectionState.listen((state) async {
      _addLog("Connection state: $state");
      
      if (state == BluetoothConnectionState.disconnected) {
        _isConnected = false;
        _connectedDevice = null;
        _bikeData = BikeData.blank;
        _dataChar = null;
        _writeChar = null;
        _addLog("Disconnected from device");
        notifyListeners();
        _startReconnect(device);
      } else if (state == BluetoothConnectionState.connected) {
        _isConnected = true;
        _connectedDevice = device;
        _reconnectTimer?.cancel();
        _reconnectAttempt = 0;
        _addLog("Connected! Checking pairing status...");
        
        // Try to pair if not already paired
        await _ensurePaired(device);
        
        await _discoverAndSubscribe(device);
        notifyListeners();
      }
    });

    try {
      await device.connect(timeout: const Duration(seconds: 15));
    } catch (e) {
      _addLog("Connection failed: $e");
      _connectionStateSubscription?.cancel();
    }
  }

  Future<void> _ensurePaired(BluetoothDevice device) async {
    try {
      final bondState = await device.bondState.first;
      _addLog("Current bond state: $bondState");
      
      if (bondState == BluetoothBondState.none) {
        _addLog("Device not paired. Attempting to pair...");
        _addLog("You may see a pairing prompt on your phone!");
        
        // This will trigger Android's pairing dialog
        await device.createBond();
        _addLog("Pairing initiated");
        
        // Wait a bit for pairing to complete
        await Future.delayed(const Duration(seconds: 3));
        
        final newBondState = await device.bondState.first;
        _addLog("New bond state: $newBondState");
      } else {
        _addLog("Device already paired: $bondState");
      }
    } catch (e) {
      _addLog("Pairing error: $e");
      _addLog("If pairing failed, try pairing manually in Android Bluetooth settings first");
    }
  }
  
  void _startReconnect(BluetoothDevice device) {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    int delaySeconds = pow(2, min(_reconnectAttempt, 4)).toInt();
    _addLog("Will reconnect in ${delaySeconds}s (Attempt ${_reconnectAttempt + 1})");
    
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
    _addLog("Disconnected manually");
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    try {
      _addLog("Discovering services...");
      List<BluetoothService> services = await device.discoverServices();
      _addLog("Found ${services.length} services");
      
      bool foundTargetService = false;
      
      for (var service in services) {
        _addLog("Service: ${service.uuid}");
        
        if (service.uuid == _TARGET_SERVICE_UUID) {
          foundTargetService = true;
          _addLog("FOUND target service FFE0!");
          
          for (var char in service.characteristics) {
            final props = char.properties;
            _addLog("  Char ${char.uuid.toString().substring(4, 8).toUpperCase()}: R:${props.read} W:${props.write} N:${props.notify}");
            
            if (char.uuid == _DATA_CHARACTERISTIC_UUID) {
              _dataChar = char;
              _addLog("  Found DATA characteristic (FFE1)");
            }
            if (char.uuid == _WRITE_CHARACTERISTIC_UUID) {
              _writeChar = char;
              _addLog("  Found WRITE characteristic (FFE2)");
            }
          }
        }
      }
      
      if (!foundTargetService) {
        _addLog("WARNING: Target service FFE0 not found!");
        _addLog("This might not be a Yezdi bike or it uses different UUIDs.");
        return;
      }

      if (_dataChar != null && _dataChar!.properties.read) {
        try {
          final initialData = await _dataChar!.read();
          _addLog("Initial read: ${_bytesToHex(initialData)}");
        } catch (e) {
          _addLog("Could not read initial data: $e");
        }
      }

      if (_dataChar != null && _dataChar!.properties.notify) {
        await _dataChar!.setNotifyValue(true);
        _dataChar!.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            _addLog("Data received: ${_bytesToHex(value)}");
            _parseBikeData(value);
          }
        });
        _addLog("Subscribed to notifications successfully!");
      } else {
        _addLog("ERROR: Cannot subscribe - NOTIFY not supported");
      }

    } catch (e) {
      _addLog("Discovery error: $e");
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  void _parseBikeData(List<int> data) {
    if (data.length < 4) {
      _addLog("Data too short: ${data.length} bytes");
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
      _addLog("Parse error: $e");
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
      _addLog("Write characteristic not available");
      return;
    }
    
    try {
      await _writeChar!.write(command, withoutResponse: true);
      _addLog("Sent command: ${_bytesToHex(command)}");
    } catch (e) {
      _addLog("Write error: $e");
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
