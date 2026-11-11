import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'airtable_sync.dart';
import 'db.dart';
import 'export.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _handset = TextEditingController();
  String _version = '';
  String _status = '';
  String _debug = '';
  bool _busy = false;
  // Delete is enabled only after the results were exported on this screen.
  bool _exported = false;
  int _stored = 0;
  int _unsynced = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final handset = await Settings.handset;
    if (!mounted) return;
    setState(() {
      _handset.text = handset;
      _version = 'v${info.version}+${info.buildNumber}';
    });
    await _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    final c = await Db.instance.counts();
    if (!mounted) return;
    setState(() {
      _stored = c['checked'] ?? 0;
      _unsynced = c['pending'] ?? 0;
    });
  }

  /// Run one action with the buttons locked, then show its message.
  Future<void> _run(String busyText, Future<String> Function() action) async {
    await Settings.setHandset(_handset.text);
    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = busyText;
    });
    final msg = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = msg;
    });
    await _refreshCounts();
  }

  Future<void> _sync() => _run('Syncing...', () async => (await AirtableSync.upload()).message);

  Future<void> _export() => _run('Exporting...', () async {
        final r = await CsvExport.shareResults();
        if (r.ok) _exported = true;
        return r.message;
      });

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete results?'),
        content: Text(
          'Delete $_stored results from this handset?\n\n'
          '${_unsynced > 0 ? 'WARNING: $_unsynced results are NOT synced to Airtable. '
              'They exist only in the CSV file you exported.\n\n' : ''}'
          'You cannot undo this.',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run('Deleting...', () async {
      final n = await Db.instance.deleteChecks();
      _exported = false;
      return '$n results deleted from the handset.';
    });
  }

  Future<void> _download() => _run('Downloading...', () async {
        final r = await AirtableSync.downloadSpecies(
          onProgress: (n) {
            if (mounted) setState(() => _status = 'Downloading... $n');
          },
        );
        return r.message;
      });

  Future<void> _test() async {
    setState(() => _debug = '');
    await _run('Testing connection...', () async {
      final r = await AirtableSync.testConnection();
      _debug = r.message;
      return r.ok ? 'Connection OK' : 'Connection problem. See details below.';
    });
  }

  @override
  void dispose() {
    _handset.dispose();
    super.dispose();
  }

  Widget _button(Widget child) => SizedBox(height: 60, child: child);

  @override
  Widget build(BuildContext context) {
    const big = TextStyle(fontSize: 20);
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
          Text(
            'Results on handset: $_stored   Not synced: $_unsynced',
            style: const TextStyle(fontSize: 17),
          ),
          const SizedBox(height: 12),
          _button(FilledButton.icon(
            onPressed: _busy ? null : _sync,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Sync records', style: big),
          )),
          const SizedBox(height: 10),
          _button(FilledButton.tonalIcon(
            onPressed: _busy || _stored == 0 ? null : _export,
            icon: const Icon(Icons.download),
            label: const Text('Download results (CSV)', style: big),
          )),
          const SizedBox(height: 10),
          _button(OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: _busy || !_exported || _stored == 0 ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete results from handset', style: TextStyle(fontSize: 18)),
          )),
          if (!_exported && _stored > 0)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Download the results first. Then you can delete them.',
                  style: TextStyle(color: Colors.grey)),
            ),
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Setup', style: big),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                _button(OutlinedButton.icon(
                  onPressed: _busy ? null : _download,
                  icon: const Icon(Icons.forest_outlined),
                  label: const Text('Download trees', style: big),
                )),
                const SizedBox(height: 10),
                _button(OutlinedButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: const Icon(Icons.network_check),
                  label: const Text('Test connection', style: big),
                )),
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
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(_version, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
