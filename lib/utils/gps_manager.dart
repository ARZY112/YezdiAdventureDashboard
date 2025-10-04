import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class GPSManager extends ChangeNotifier {
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  double _currentSpeed = 0.0; // km/h
  
  double get currentSpeed => _currentSpeed;
  Position? get currentPosition => _currentPosition;
  
  bool _isTracking = false;
  bool get isTracking => _isTracking;

  Future<bool> requestPermissions() async {
    var status = await Permission.location.request();
    return status.isGranted;
  }

  Future<void> startTracking() async {
    bool hasPermission = await requestPermissions();
    if (!hasPermission) {
      print("❌ Location permission denied");
      return;
    }

    _isTracking = true;
    notifyListeners();

    LocationSettings locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _currentPosition = position;
      _currentSpeed = position.speed * 3.6;
      
      print("📍 GPS Speed: ${_currentSpeed.toStringAsFixed(1)} km/h");
      notifyListeners();
    });
  }

  void stopTracking() {
    _positionStream?.cancel();
    _isTracking = false;
    _currentSpeed = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}

