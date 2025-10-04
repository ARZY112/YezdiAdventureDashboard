import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'screens/dashboard_screen.dart';
import 'utils/ble_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request permissions BEFORE app starts
  await requestPermissions();
  
  runApp(YezdiDashboardApp());
}

Future<void> requestPermissions() async {
  // Request all necessary permissions
  Map<Permission, PermissionStatus> statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
    Permission.locationWhenInUse,
  ].request();

  // Check if any were denied
  bool allGranted = statuses.values.every((status) => status.isGranted);
  
  if (!allGranted) {
    print("⚠️ Some permissions denied!");
    statuses.forEach((permission, status) {
      print("$permission: $status");
    });
    
    // If permanently denied, open app settings
    bool anyPermanentlyDenied = statuses.values.any((status) => status.isPermanentlyDenied);
    if (anyPermanentlyDenied) {
      print("Opening app settings...");
      await openAppSettings();
    }
  } else {
    print("✅ All permissions granted!");
  }
}

class YezdiDashboardApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => BLEManager(),
      child: MaterialApp(
        title: 'Yezdi Adventure Dashboard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: Colors.cyanAccent,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.dark(
            primary: Colors.cyanAccent,
            secondary: Colors.amberAccent,
          ),
          textTheme: TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white70),
          ),
          iconTheme: IconThemeData(color: Colors.cyanAccent),
        ),
        home: DashboardScreen(),
      ),
    );
  }
}
