import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../utils/ble_manager.dart';

class ConnectivityScreen extends StatelessWidget {
  const ConnectivityScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bleManager = Provider.of<BLEManager>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Connectivity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Export Logs",
            onPressed: bleManager.exportLogs,
          )
        ],
      ),
      body: Column(
        children: [
          // Scan and Disconnect Buttons
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Scan'),
                  onPressed: bleManager.isScanning ? null : bleManager.startScan,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: const Text('Disconnect'),
                  onPressed: bleManager.isConnected ? bleManager.disconnectFromDevice : null,
                ),
              ],
            ),
          ),
          
          // Scanning Progress Indicator
          if (bleManager.isScanning) const LinearProgressIndicator(),
          
          // Connection Status
          ListTile(
            title: const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              bleManager.isConnected 
                ? "Connected to ${bleManager.connectedDevice?.platformName ?? 'Unknown'}" 
                : "Disconnected"
            ),
            trailing: Icon(
              bleManager.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: bleManager.isConnected ? Colors.green : Colors.red,
            ),
          ),
          
          const Divider(),
          
          // === NEW: Discovered Services Section ===
          if (bleManager.isConnected && bleManager.discoveredServiceUUIDs.isNotEmpty) ...[
            ExpansionTile(
              leading: const Icon(Icons.storage, color: Colors.cyanAccent, size: 20),
              title: const Text(
                '📦 Discovered Services',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${bleManager.discoveredServiceUUIDs.length} services',
                style: const TextStyle(fontSize: 11),
              ),
              initiallyExpanded: true, // Auto-expand when connected
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.grey[900],
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: bleManager.discoveredServiceUUIDs.length,
                    itemBuilder: (context, index) {
                      final uuid = bleManager.discoveredServiceUUIDs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.circle, size: 5, color: Colors.cyanAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                uuid,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: uuid));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Service UUID copied!'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            
            ExpansionTile(
              leading: const Icon(Icons.list_alt, color: Colors.amberAccent, size: 20),
              title: const Text(
                '📝 Characteristics',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${bleManager.discoveredCharacteristicUUIDs.length} characteristics',
                style: const TextStyle(fontSize: 11),
              ),
              initiallyExpanded: true,
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.grey[900],
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: bleManager.discoveredCharacteristicUUIDs.length,
                    itemBuilder: (context, index) {
                      final uuid = bleManager.discoveredCharacteristicUUIDs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.circle, size: 5, color: Colors.amberAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                uuid,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: uuid));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Characteristic UUID copied!'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            
            const Divider(),
          ],
          
          // Discovered Devices Section
          Text("Discovered Devices", style: Theme.of(context).textTheme.titleLarge),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: bleManager.scanResults.length,
              itemBuilder: (context, index) {
                final result = bleManager.scanResults[index];
                final deviceName = result.device.platformName.isEmpty 
                    ? "Unknown Device" 
                    : result.device.platformName;
                final isYezdi = deviceName.toLowerCase().contains("yezdi") || 
                               deviceName.toLowerCase().contains("adventure");
                
                return ListTile(
                  leading: Icon(
                    Icons.motorcycle, 
                    color: isYezdi ? Theme.of(context).colorScheme.primary : Colors.grey
                  ),
                  title: Text(deviceName),
                  subtitle: Text(result.device.remoteId.toString()),
                  trailing: ElevatedButton(
                    child: const Text('Connect'),
                    onPressed: () => bleManager.connectToDevice(result.device),
                  ),
                );
              },
            ),
          ),
          
          const Divider(),
          
          // Logs Section
          Text("Logs", style: Theme.of(context).textTheme.titleLarge),
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black54,
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  bleManager.logs, 
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
