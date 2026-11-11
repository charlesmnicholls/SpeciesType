import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'airtable_sync.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _handset = TextEditingController();
  String _version = '';
  bool _hasKey = false;
  String _status = '';
  String _debug = '';
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
      _handset.text = handset;
      _hasKey = pat.isNotEmpty;
      _version = 'v${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _download() async {
    await Settings.setHandset(_handset.text);
    if (!mounted) return;
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
    await Settings.setHandset(_handset.text);
    if (!mounted) return;
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

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _status = 'Testing connection...';
      _debug = '';
    });
    final r = await AirtableSync.testConnection();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r.ok ? 'Connection OK' : 'Connection problem. See details below.';
      _debug = r.message;
    });
  }

  @override
  void dispose() {
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
            onChanged: (v) => Settings.setHandset(v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(_hasKey ? Icons.check_circle : Icons.error,
                  color: _hasKey ? Colors.green.shade700 : Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _hasKey ? 'Airtable key: built into app' : 'Airtable key: MISSING from this build',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
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
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: const Icon(Icons.network_check),
              label: const Text('Test connection', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(height: 16),
          Text(_status, style: const TextStyle(fontSize: 18)),
          if (_debug.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _debug,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _debug));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Details copied')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy details'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(_version, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
