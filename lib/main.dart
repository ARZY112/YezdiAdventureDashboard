import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/permission_screen.dart';
import 'utils/ble_manager.dart';
import 'utils/gps_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YezdiDashboardApp());
}

class YezdiDashboardApp extends StatelessWidget {
  const YezdiDashboardApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BLEManager()),
        ChangeNotifierProvider(create: (_) => GPSManager()),
      ],
      child: MaterialApp(
        title: 'Yezdi Adventure Dashboard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: Colors.cyanAccent,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.cyanAccent,
            secondary: Colors.amberAccent,
          ),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
            bodyMedium: TextStyle(color: Colors.white70),
          ),
          iconTheme: const IconThemeData(color: Colors.cyanAccent),
        ),
        home: const PermissionScreen(),
      ),
    );
  }
}
