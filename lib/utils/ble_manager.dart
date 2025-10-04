// ignore_for_file: avoid_print

import 'dart:async';
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

  List<String> discoveredServiceUUIDs = [];
  List<String> discoveredCharacteristicUUIDs = [];

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  List<ScanResult> get scanResults => _scanResults;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  BikeData get bikeData => _bikeData;
  String get logs => _log;

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
    
    final permissionsGranted = await _checkPermissions();
    if (!permissionsGranted) {
      _addLog("ERROR: Permissions not granted!");
      return;
    }

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
      Permission.bluetooth,
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
        discoveredServiceUUIDs.clear();
        discoveredCharacteristicUUIDs.clear();
        _addLog("Disconnected from device");
        notifyListeners();
        _startReconnect(device);
      } else if (state == BluetoothConnectionState.connected) {
        _isConnected = true;
        _connectedDevice = device;
        _reconnectTimer?.cancel();
        _reconnectAttempt = 0;
        _addLog("Connected!");
        
        bool isPaired = await _ensurePaired(device);
        
        if (isPaired) {
          _addLog("Device is paired. Waiting before discovery...");
          await Future.delayed(Duration(seconds: 3));
          await _discoverAndSubscribe(device);
        } else {
          _addLog("Pairing incomplete. Trying discovery anyway...");
          await Future.delayed(Duration(seconds: 2));
          await _discoverAndSubscribe(device);
        }
        
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

  Future<bool> _ensurePaired(BluetoothDevice device) async {
    try {
      final bondState = await device.bondState.first;
      _addLog("Current bond state: $bondState");
      
      if (bondState == BluetoothBondState.bonded) {
        _addLog("Already paired!");
        return true;
      }
      
      if (bondState == BluetoothBondState.none) {
        _addLog("Device not paired. Attempting pairing...");
        _addLog("You may see a pairing prompt - ACCEPT IT!");
        
        try {
          await device.createBond();
          await Future.delayed(const Duration(seconds: 5));
          
          final newBondState = await device.bondState.first;
          _addLog("New bond state: $newBondState");
          
          if (newBondState == BluetoothBondState.bonded) {
            _addLog("Pairing successful!");
            return true;
          } else {
            _addLog("Pairing incomplete: $newBondState");
            return false;
          }
        } catch (e) {
          _addLog("Pairing error: $e");
          return false;
        }
      }
      
      return bondState == BluetoothBondState.bonded;
    } catch (e) {
      _addLog("Bond check error: $e");
      return false;
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
      _addLog("Discovering ALL services...");
      
      List<BluetoothService> services = await device.discoverServices();
      _addLog("Found ${services.length} services");
      
      discoveredServiceUUIDs.clear();
      discoveredCharacteristicUUIDs.clear();
      
      BluetoothCharacteristic? bestDataChar;
      BluetoothCharacteristic? bestWriteChar;
      
      _addLog("\n========== SERVICE DISCOVERY ==========");
      
      for (var service in services) {
        String serviceUUID = service.uuid.toString().toUpperCase();
        discoveredServiceUUIDs.add(serviceUUID);
        _addLog("Service: $serviceUUID");
        
        if (serviceUUID.startsWith("0000180") || serviceUUID.startsWith("0000181")) {
          _addLog("   Skipping standard service");
          continue;
        }
        
        for (var char in service.characteristics) {
          String charUUID = char.uuid.toString().toUpperCase();
          discoveredCharacteristicUUIDs.add(charUUID);
          
          final props = char.properties;
          _addLog("   Char: ${charUUID.length > 8 ? charUUID.substring(4, 8) : charUUID}");
          _addLog("      Read=${props.read}, Write=${props.write}, "
                  "Notify=${props.notify}, WriteNoResp=${props.writeWithoutResponse}");
          
          if (props.notify && bestDataChar == null) {
            bestDataChar = char;
            _addLog("      Selected as DATA characteristic");
          }
          
          if ((props.write || props.writeWithoutResponse) && bestWriteChar == null) {
            bestWriteChar = char;
            _addLog("      Selected as WRITE characteristic");
          }
          
          if (props.read) {
            try {
              await Future.delayed(Duration(milliseconds: 200));
              List<int> value = await char.read();
              if (value.isNotEmpty) {
                _addLog("      Read: ${_bytesToHex(value)}");
              }
            } catch (e) {
              _addLog("      Read failed: $e");
            }
          }
        }
      }
      
      _addLog("======================================\n");
      
      _dataChar = bestDataChar;
      _writeChar = bestWriteChar;
      
      if (_dataChar == null) {
        _addLog("WARNING: No NOTIFY characteristic found!");
        _addLog("Device may not send continuous data.");
        return;
      }
      
      _addLog("Using DATA characteristic: ${_dataChar!.uuid}");
      if (_writeChar != null) {
        _addLog("Using WRITE characteristic: ${_writeChar!.uuid}");
      }
      
      // Subscribe to notifications
      try {
        await _dataChar!.setNotifyValue(true);
        _addLog("Subscribed to notifications!");
        
        _dataChar!.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            _addLog("Data received: ${_bytesToHex(value)}");
            _parseBikeData(value);
          }
        }, onError: (e) {
          _addLog("Notification error: $e");
        });
        
        // === AUTHENTICATION & ACTIVATION SEQUENCE ===
        if (_writeChar != null) {
          _addLog("Attempting authentication sequence...");
          
          try {
            await Future.delayed(Duration(milliseconds: 500));
            
            // Try multiple common patterns
            // Pattern 1: Simple enable
            await _writeChar!.write([0x01], withoutResponse: true);
            _addLog("Sent: Enable command (0x01)");
            await Future.delayed(Duration(milliseconds: 300));
            
            // Pattern 2: Standard auth token
            await _writeChar!.write([0xAA, 0x55], withoutResponse: true);
            _addLog("Sent: Auth token (0xAA 0x55)");
            await Future.delayed(Duration(milliseconds: 300));
            
            // Pattern 3: Start telemetry
            await _writeChar!.write([0xFF, 0x01, 0x00], withoutResponse: true);
            _addLog("Sent: Start telemetry");
            await Future.delayed(Duration(milliseconds: 300));
            
            // Pattern 4: Alternative auth
            await _writeChar!.write([0x01, 0x01], withoutResponse: true);
            _addLog("Sent: Alt auth (0x01 0x01)");
            
            _addLog("Authentication sequence complete");
            _addLog("Waiting for data stream...");
            _addLog("If no data arrives in 10s, reconnect or check logs");
            
          } catch (e) {
            _addLog("Authentication error: $e");
          }
        } else {
          _addLog("No write characteristic - cannot send commands");
        }
        
      } catch (e) {
        _addLog("Failed to subscribe: $e");
      }

    } catch (e) {
      _addLog("Discovery error: $e");
    }
    
    notifyListeners();
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  void _parseBikeData(List<int> data) {
    if (data.isEmpty) {
      _addLog("Empty data received");
      return;
    }

    _addLog("Parsing ${data.length} bytes...");

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
      
      _addLog("Parsed: Speed=${_bikeData.speed}, RPM=${_bikeData.rpm}, "
              "Gear=${_bikeData.gear}, Fuel=${(_bikeData.fuel * 100).toStringAsFixed(0)}%");
      
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
