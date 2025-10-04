import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../utils/classic_bt_manager.dart';

class ConnectivityScreen extends StatelessWidget {
  const ConnectivityScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final btManager = Provider.of<ClassicBTManager>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Connectivity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Export Logs",
            onPressed: btManager.exportLogs,
          )
        ],
      ),
      body: Column(
        children: [
          // Refresh and Disconnect Buttons
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Paired'),
                  onPressed: btManager.getPairedDevices,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: const Text('Disconnect'),
                  onPressed: btManager.isConnected ? btManager.disconnect : null,
                ),
              ],
            ),
          ),
          
          // Connection Status
          ListTile(
            title: const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              btManager.isConnected 
                ? "Connected via Classic Bluetooth" 
                : "Disconnected"
            ),
            trailing: Icon(
              btManager.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: btManager.isConnected ? Colors.green : Colors.red,
            ),
          ),
          
          const Divider(),
          
          // Paired Devices Section
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "Paired Devices (Classic Bluetooth)", 
              style: Theme.of(context).textTheme.titleLarge
            ),
          ),
          
          // Info card
          if (btManager.pairedDevices.isEmpty)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade900,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Go to Android Settings → Bluetooth and pair your bike first!',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: btManager.pairedDevices.length,
              itemBuilder: (context, index) {
                final device = btManager.pairedDevices[index];
                final deviceName = device.name ?? "Unknown Device";
                final isYezdi = deviceName.toLowerCase().contains("yezdi") || 
                               deviceName.toLowerCase().contains("my yezdi") ||
                               deviceName.toLowerCase().contains("adventure");
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: isYezdi ? Colors.cyan.shade900 : Colors.grey.shade800,
                  child: ListTile(
                    leading: Icon(
                      Icons.motorcycle, 
                      color: isYezdi ? Colors.cyanAccent : Colors.grey,
                      size: 32,
                    ),
                    title: Text(
                      deviceName,
                      style: TextStyle(
                        fontWeight: isYezdi ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      device.address,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                    trailing: ElevatedButton.icon(
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Connect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isYezdi ? Colors.cyanAccent : null,
                        foregroundColor: isYezdi ? Colors.black : null,
                      ),
                      onPressed: () => btManager.connectToDevice(device),
                    ),
                  ),
                );
              },
            ),
          ),
          
          const Divider(),
          
          // Logs Section
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("Connection Logs", style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black87,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  btManager.logs.isEmpty ? "[No logs yet]" : btManager.logs, 
                  style: const TextStyle(
                    fontFamily: 'monospace', 
                    fontSize: 10,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
