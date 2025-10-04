import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'dashboard_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({Key? key}) : super(key: key);

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isChecking = true;
  String _status = "Checking permissions...";

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    setState(() {
      _status = "Requesting permissions...";
    });

    Map<Permission, PermissionStatus> statuses = {};

    // Android version ke according permissions request karo
    if (Platform.isAndroid) {
      // Android 12+ (API 31+) ke liye
      statuses = await [
        Permission.bluetooth,        // Android 11 aur neeche ke liye
        Permission.bluetoothScan,    // Android 12+ ke liye
        Permission.bluetoothConnect, // Android 12+ ke liye
        Permission.location,         // Sab versions ke liye (Android 11 mein mandatory)
      ].request();
    }

    // Check karein ki zaroori permissions granted hain ya nahi
    bool bluetoothGranted = (statuses[Permission.bluetooth]?.isGranted ?? true) ||
                           (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
    bool locationGranted = statuses[Permission.location]?.isGranted ?? false;

    if (bluetoothGranted && locationGranted) {
      // Sab permissions granted hain - Dashboard pe navigate karo
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } else {
      // Kuch permissions denied hain
      setState(() {
        _isChecking = false;
        
        if (!bluetoothGranted) {
          _status = "Bluetooth permission denied";
        } else if (!locationGranted) {
          _status = "Location permission denied";
        } else {
          _status = "Some permissions were denied";
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.bluetooth_searching,
                size: 100,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 40),
              Text(
                'Yezdi Dashboard',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 40),
              if (!_isChecking) ...[
                const Text(
                  'This app needs:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text('• Bluetooth permissions'),
                const Text('• Location permissions (required for BLE on Android)'),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _isChecking = true;
                      _status = "Opening settings...";
                    });
                    await openAppSettings();
                    // Settings se wapas aane pe wait karo aur phir recheck karo
                    await Future.delayed(Duration(milliseconds: 500));
                    if (mounted) {
                      setState(() {
                        _isChecking = false;
                        _status = "Please grant all permissions and try again";
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  ),
                  child: const Text('Open Settings'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _checkAndRequestPermissions,
                  child: const Text('Try Again'),
                ),
              ] else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
