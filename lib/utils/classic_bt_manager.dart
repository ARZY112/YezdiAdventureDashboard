import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import '../models/bike_data.dart';

class ClassicBTManager extends ChangeNotifier {
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection? _connection;
  
  bool _isConnected = false;
  BikeData _bikeData = BikeData.blank;
  String _log = "";
  List<BluetoothDevice> _pairedDevices = [];
  StreamSubscription<Uint8List>? _dataSubscription;

  bool get isConnected => _isConnected;
  BikeData get bikeData => _bikeData;
  String get logs => _log;
  List<BluetoothDevice> get pairedDevices => _pairedDevices;

  ClassicBTManager() {
    _init();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }

  Future<void> _init() async {
    _addLog("Initializing Classic Bluetooth...");
    
    bool? isAvailable = await _bluetooth.isAvailable;
    if (isAvailable == false) {
      _addLog("ERROR: Bluetooth not available");
      return;
    }

    bool? isEnabled = await _bluetooth.isEnabled;
    if (isEnabled == false) {
      _addLog("Requesting Bluetooth enable...");
      await _bluetooth.requestEnable();
    }

    await getPairedDevices();
  }

  void _addLog(String message) {
    print(message);
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    _log = "$_log[$timestamp] $message\n";
    notifyListeners();
  }

  Future<void> exportLogs() async {
    _addLog("Logs exported to console");
    print("=== YEZDI DASHBOARD LOGS ===");
    print(_log);
    print("=== END LOGS ===");
  }

  Future<void> getPairedDevices() async {
    _addLog("Getting paired devices...");
    try {
      List<BluetoothDevice> devices = await _bluetooth.getBondedDevices();
      _pairedDevices = devices;
      _addLog("Found ${devices.length} paired devices");
      for (var device in devices) {
        _addLog("  - ${device.name ?? 'Unknown'} (${device.address})");
      }
      notifyListeners();
    } catch (e) {
      _addLog("Error: $e");
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnected) {
      _addLog("Disconnecting previous connection...");
      await disconnect();
    }

    _addLog("Connecting to ${device.name ?? 'Unknown'}...");
    
    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      _isConnected = true;
      _addLog("✅ Connected to ${device.name}!");
      
      _dataSubscription = _connection!.input!.listen(
        _onDataReceived,
        onDone: () {
          _addLog("❌ Disconnected by remote");
          _isConnected = false;
          _bikeData = BikeData.blank;
          notifyListeners();
        },
        onError: (error) {
          _addLog("Connection error: $error");
        },
      );

      notifyListeners();
    } catch (e) {
      _addLog("❌ Connection failed: $e");
      _isConnected = false;
      notifyListeners();
    }
  }

  void _onDataReceived(Uint8List data) {
    _addLog("📥 Data: ${_bytesToHex(data)} (${data.length} bytes)");
    _parseBikeData(data);
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  void _parseBikeData(Uint8List data) {
    if (data.isEmpty) return;

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
      
      _addLog("✅ Speed=${_bikeData.speed} RPM=${_bikeData.rpm} Gear=${_bikeData.gear}");
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

  Future<void> disconnect() async {
    _addLog("Disconnecting...");
    _dataSubscription?.cancel();
    _connection?.dispose();
    _isConnected = false;
    _bikeData = BikeData.blank;
    notifyListeners();
  }
}
