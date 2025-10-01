import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // TODO: Load these values from SharedPreferences
  bool _speedWarning = true;
  int _navMode = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('120 km/h Speed Warning'),
            subtitle: const Text('Blinks the speedometer when exceeding 120 km/h.'),
            value: _speedWarning,
            onChanged: (val) => setState(() => _speedWarning = val),
          ),
          const Divider(),
          const ListTile(
            title: Text('Navigation Mode'),
            subtitle: Text('Choose what appears on the right panel.'),
          ),
          RadioListTile<int>(
            title: const Text('Off (3D Bike Model)'),
            value: 0,
            groupValue: _navMode,
            onChanged: (val) => setState(() => _navMode = val!),
          ),
          RadioListTile<int>(
            title: const Text('Directions View (Faded Map)'),
            value: 1,
            groupValue: _navMode,
            onChanged: (val) => setState(() => _navMode = val!),
          ),
          RadioListTile<int>(
            title: const Text('Full Map View'),
            value: 2,
            groupValue: _navMode,
            onChanged: (val) => setState(() => _navMode = val!),
          ),
          const Divider(),
          ListTile(
            title: const Text('Debug Mode'),
            subtitle: const Text('Allows manual entry of UUIDs and keys.'),
            trailing: const Icon(Icons.developer_mode),
            onTap: () {
              // TODO: Navigate to a dedicated debug screen
            },
          ),
        ],
      ),
    );
  }
}
