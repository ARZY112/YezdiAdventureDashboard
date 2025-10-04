import 'package:flutter/material.dart';
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
          if (bleManager.isScanning) const LinearProgressIndicator(),
          ListTile(
            title: const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              bleManager.isConnected 
              ? "Connected to ${bleManager.connectedDevice?.name ?? 'Unknown'}" 
              : "Disconnected"
            ),
            trailing: Icon(
                bleManager.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: bleManager.isConnected ? Colors.green : Colors.red,
            ),
          ),
          const Divider(),
          Text("Discovered Devices", style: Theme.of(context).textTheme.titleLarge),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: bleManager.scanResults.length,
              itemBuilder: (context, index) {
                final result = bleManager.scanResults[index];
                final isYezdi = result.device.name.toLowerCase().contains("yezdi") || result.device.name.toLowerCase().contains("adventure");
                return ListTile(
                  leading: Icon(Icons.motorcycle, color: isYezdi ? Theme.of(context).colorScheme.primary : Colors.grey),
                  title: Text(result.device.name.isEmpty ? "Unknown Device" : result.device.name),
                  subtitle: Text(result.device.id.toString()),
                  trailing: ElevatedButton(
                    child: const Text('Connect'),
                    onPressed: () => bleManager.connectToDevice(result.device),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          Text("Logs", style: Theme.of(context).textTheme.titleLarge),
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black54,
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(bleManager.logs, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
              ),
            ),
          )
        ],
      ),
    );
  }
}
