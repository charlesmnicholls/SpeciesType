import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'airtable_sync.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _pat = TextEditingController();
  final _handset = TextEditingController();
  String _version = '';
  String _status = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final pat = await Settings.pat;
    final handset = await Settings.handset;
    if (!mounted) return;
    setState(() {
      _pat.text = pat;
      _handset.text = handset;
      _version = 'v${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _saveFields() async {
    await Settings.setPat(_pat.text);
    await Settings.setHandset(_handset.text);
  }

  Future<void> _download() async {
    await _saveFields();
    setState(() {
      _busy = true;
      _status = 'Downloading...';
    });
    final r = await AirtableSync.downloadSpecies(
      onProgress: (n) {
        if (mounted) setState(() => _status = 'Downloading... $n');
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r.message;
    });
  }

  Future<void> _upload() async {
    await _saveFields();
    setState(() {
      _busy = true;
      _status = 'Sending...';
    });
    final r = await AirtableSync.upload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r.message;
    });
  }

  @override
  void dispose() {
    _pat.dispose();
    _handset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _handset,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(labelText: 'Handset name', border: OutlineInputBorder()),
            onChanged: (_) => _saveFields(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pat,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(labelText: 'Airtable key', border: OutlineInputBorder()),
            onChanged: (_) => _saveFields(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 64,
            child: FilledButton(
              onPressed: _busy ? null : _download,
              child: const Text('Download trees', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: FilledButton.tonal(
              onPressed: _busy ? null : _upload,
              child: const Text('Send results', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(height: 16),
          Text(_status, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 24),
          Text(_version, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
