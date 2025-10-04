import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/ble_manager.dart';
import '../utils/gps_manager.dart';
import '../utils/music_manager.dart';
import '../models/bike_data.dart';
import 'connectivity_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  bool _isMenuVisible = false;
  late AnimationController _speedBlinkController;
  GoogleMapController? _mapController;

  int _odometerViewIndex = 0;
  final List<String> _odometerLabels = ['ODO', 'DTE', 'TRIP A', 'AFE A', 'TRIP B', 'AFE B'];

  @override
  void initState() {
    super.initState();
    _speedBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gpsManager = Provider.of<GPSManager>(context, listen: false);
      gpsManager.startTracking();
    });
  }

  @override
  void dispose() {
    _speedBlinkController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _onOdometerSwipe(DragEndDetails details) {
    if (details.primaryVelocity == 0) return;
    setState(() {
      if (details.primaryVelocity! < 0) {
        _odometerViewIndex = (_odometerViewIndex + 1) % _odometerLabels.length;
      } else {
        _odometerViewIndex = (_odometerViewIndex - 1 + _odometerLabels.length) % _odometerLabels.length;
      }
    });
  }
  
  Widget _getOdometerValueWidget(BikeData data, bool isConnected) {
    String value;
    switch(_odometerLabels[_odometerViewIndex]) {
      case 'ODO': value = data.odo.toStringAsFixed(1); break;
      case 'DTE': value = data.dte.toStringAsFixed(0); break;
      case 'TRIP A': value = data.tripA.toStringAsFixed(1); break;
      case 'AFE A': value = data.afeA.toStringAsFixed(1); break;
      case 'TRIP B': value = data.tripB.toStringAsFixed(1); break;
      case 'AFE B': value = data.afeB.toStringAsFixed(1); break;
      default: value = '--';
    }
    return Text(
      isConnected ? value : '--',
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace')
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Consumer3<BLEManager, GPSManager, MusicManager>(
        builder: (context, bleManager, gpsManager, musicManager, child) {
          final bikeData = bleManager.bikeData;
          final isConnected = bleManager.isConnected;

          if (gpsManager.currentPosition != null && _mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLng(
                LatLng(
                  gpsManager.currentPosition!.latitude,
                  gpsManager.currentPosition!.longitude,
                ),
              ),
            );
          }

          return Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/yezdi_logo.png'),
                    fit: BoxFit.contain,
                    opacity: 0.05,
                  ),
                ),
              ),

              SafeArea(
                child: Row(
                  children: [
                    _buildLeftMenu(screenSize),
                    Expanded(flex: 3, child: _buildSpeedometerSection(bikeData, isConnected, gpsManager)),
                    Expanded(flex: 1, child: _buildCenterGauges(bikeData, isConnected, gpsManager)),
                    Expanded(flex: 3, child: _buildRightPanel(context, gpsManager)),
                  ],
                ),
              ),

              _buildTopIndicators(bikeData, isConnected),
              _buildMusicControls(context, musicManager),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLeftMenu(Size screenSize) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isMenuVisible ? screenSize.width * 0.2 : 60,
      curve: Curves.easeInOut,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(_isMenuVisible ? Icons.arrow_back_ios : Icons.menu, size: 30),
            onPressed: () => setState(() => _isMenuVisible = !_isMenuVisible),
          ),
          const SizedBox(height: 20),
          _menuItem(Icons.bluetooth, "Connectivity", () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectivityScreen()));
          }),
          _menuItem(Icons.settings, "Settings", () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }),
          _menuItem(Icons.motorcycle, "About", () {}),
        ],
      ),
    );
  }
  
  Widget _menuItem(IconData icon, String text, VoidCallback onPressed) {
    if (!_isMenuVisible) {
      return IconButton(icon: Icon(icon, size: 30), onPressed: onPressed);
    }
    return ListTile(
      leading: Icon(icon, size: 30),
      title: Text(text, overflow: TextOverflow.ellipsis),
      onTap: onPressed,
    );
  }

  Widget _buildSpeedometerSection(BikeData data, bool isConnected, GPSManager gpsManager) {
    final speed = gpsManager.isTracking 
        ? gpsManager.currentSpeed.round()
        : (isConnected ? data.speed : 0);
    
    Color speedColor = speed >= 100 ? Colors.redAccent : Theme.of(context).colorScheme.primary;
    
    Widget speedText = Text(
      speed.toString(),
      style: TextStyle(
        fontSize: 100,
        fontWeight: FontWeight.w900,
        fontFamily: 'monospace',
        color: speedColor,
      ),
    );
    
    if (speed >= 120) {
      speedText = FadeTransition(opacity: _speedBlinkController, child: speedText);
    }
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        speedText,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("km/h", style: TextStyle(color: Colors.white70)),
            if (gpsManager.isTracking) ...[
              const SizedBox(width: 8),
              const Icon(Icons.gps_fixed, size: 16, color: Colors.green),
            ],
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: Icon(gpsManager.isTracking ? Icons.gps_fixed : Icons.gps_off),
          label: Text(gpsManager.isTracking ? "GPS ON" : "Start GPS"),
          style: ElevatedButton.styleFrom(
            backgroundColor: gpsManager.isTracking ? Colors.green : Colors.grey,
          ),
          onPressed: () {
            if (gpsManager.isTracking) {
              gpsManager.stopTracking();
            } else {
              gpsManager.startTracking();
            }
          },
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onHorizontalDragEnd: _onOdometerSwipe,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10)
            ),
            child: Column(
              children: [
                Text(_odometerLabels[_odometerViewIndex], 
                  style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 5),
                _getOdometerValueWidget(data, isConnected),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildCenterGauges(BikeData data, bool isConnected, GPSManager gpsManager) {
    final speed = gpsManager.isTracking ? gpsManager.currentSpeed.round() : data.speed;
    final rpm = (speed * 70).clamp(0, 9000);
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(isConnected ? "Gear ${data.gear == 0 ? 'N' : data.gear}" : "--", 
          style: const TextStyle(fontSize: 20)),
        Text(isConnected ? data.mode : "--", 
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        const Text("RPM"),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: rpm / 9000.0,
          backgroundColor: Colors.grey.shade800,
          valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.secondary),
        ),
        const SizedBox(height: 30),
        const Text("Fuel"),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: isConnected ? data.fuel : 0.0,
          backgroundColor: Colors.grey.shade800,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
        ),
      ],
    );
  }
  
  Widget _buildRightPanel(BuildContext context, GPSManager gpsManager) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: gpsManager.currentPosition != null
                ? LatLng(
                    gpsManager.currentPosition!.latitude,
                    gpsManager.currentPosition!.longitude,
                  )
                : const LatLng(26.1445, 91.7362),
            zoom: 16,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          compassEnabled: true,
          zoomControlsEnabled: false,
          mapType: MapType.normal,
          onMapCreated: (controller) {
            _mapController = controller;
          },
        ),
      ),
    );
  }
  
  Widget _buildTopIndicators(BikeData data, bool isConnected) {
    return Positioned(
      top: 40,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _indicatorIcon(Icons.lightbulb, isConnected && data.highBeam, Colors.blue),
          _indicatorIcon(Icons.warning_amber, isConnected && data.hazard, Colors.orange),
          _indicatorIcon(Icons.miscellaneous_services, isConnected && data.engineCheck, Colors.yellow),
          _indicatorIcon(Icons.battery_alert, isConnected && data.batteryWarning, Colors.red),
          const SizedBox(width: 20),
          Text(
            DateFormat('hh:mm a').format(DateTime.now()),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
  
  Widget _indicatorIcon(IconData icon, bool isActive, Color activeColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Icon(icon, color: isActive ? activeColor : Colors.grey.shade800, size: 28),
    );
  }

  Widget _buildMusicControls(BuildContext context, MusicManager musicManager) {
    if (!musicManager.isPlaying) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, color: Colors.cyanAccent, size: 32),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    musicManager.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    musicManager.artist,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.equalizer, color: Colors.green, size: 24),
          ],
        ),
      ),
    );
  }
}
