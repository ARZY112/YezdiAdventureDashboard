import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/permission_screen.dart';
import 'utils/classic_bt_manager.dart';  // CHANGED FROM ble_manager

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(YezdiDashboardApp());
}

class YezdiDashboardApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ClassicBTManager(),  // CHANGED FROM BLEManager
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
        home: PermissionScreen(), // Start with permission screen
      ),
    );
  }
}
