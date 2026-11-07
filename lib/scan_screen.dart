import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import 'airtable_sync.dart';
import 'config.dart';
import 'db.dart';
import 'settings_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  Map<String, Object?>? _tree;
  Map<String, Object?>? _existing;
  String? _error;
  Map<String, int> _counts = {'total': 0, 'checked': 0, 'changed': 0, 'pending': 0};
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _refreshCounts();
    if (!mounted) return;
    if ((await Settings.handset).isEmpty) {
      await _askHandset();
    }
    if (!mounted) return;
    if (_counts['total'] == 0) {
      _snack('Open Settings and tap Download trees.');
    }
    _focus.requestFocus();
  }

  Future<void> _askHandset() async {
    final c = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Handset name'),
        content: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(fontSize: 22),
          decoration: const InputDecoration(hintText: 'For example: X41-03'),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              if (c.text.trim().isEmpty) return;
              await Settings.setHandset(c.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshCounts() async {
    final c = await Db.instance.counts();
    if (!mounted) return;
    setState(() => _counts = c);
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontSize: 18))));
  }

  Future<void> _buzz() async {
    try {
      if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 80);
    } catch (_) {}
  }

  Future<void> _lookup(String raw) async {
    final code = raw.replaceAll(RegExp(r'[\r\n\s]'), '');
    _ctrl.clear();
    if (code.isEmpty) {
      _focus.requestFocus();
      return;
    }
    final tree = await Db.instance.getTree(code);
    final existing = tree == null ? null : await Db.instance.getCheck(code);
    if (!mounted) return;
    await _buzz();
    setState(() {
      _tree = tree;
      _existing = existing;
      _error = tree == null ? 'Barcode $code is not in the database.' : null;
    });
    if (tree == null) _focus.requestFocus();
  }

  Future<void> _save(String confirmed) async {
    final t = _tree;
    if (t == null) return;
    await Db.instance.saveCheck(
      barcode: t['barcode'] as String,
      plot: (t['plot'] as String?) ?? '',
      recorded: (t['species'] as String?) ?? '',
      confirmed: confirmed,
      handset: await Settings.handset,
    );
    await _buzz();
    if (!mounted) return;
    setState(() {
      _tree = null;
      _existing = null;
      _error = null;
    });
    await _refreshCounts();
    _snack('Saved: $confirmed');
    _focus.requestFocus();
    if ((_counts['pending'] ?? 0) >= 20 && !_syncing) _sync(quiet: true);
  }

  Future<void> _change() async {
    final current = (_tree?['species'] as String?) ?? '';
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Correct species', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            for (final s in Config.species)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  height: 60,
                  child: FilledButton.tonal(
                    onPressed: s == current ? null : () => Navigator.pop(ctx, s),
                    child: Text(s, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice != null) await _save(choice);
    if (mounted) _focus.requestFocus();
  }

  Future<void> _sync({bool quiet = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final r = await AirtableSync.upload();
    if (!mounted) return;
    setState(() => _syncing = false);
    await _refreshCounts();
    if (!quiet || !r.ok) _snack(r.message);
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _refreshCounts();
    if (mounted) _focus.requestFocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _counts['pending'] ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Species Check'),
        actions: [
          IconButton(
            iconSize: 32,
            tooltip: 'Send data',
            onPressed: _syncing ? null : () => _sync(),
            icon: _syncing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                : Badge(
                    isLabelVisible: pending > 0,
                    label: Text('$pending'),
                    child: const Icon(Icons.cloud_upload_outlined),
                  ),
          ),
          IconButton(
            iconSize: 32,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              style: const TextStyle(fontSize: 26),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Scan barcode',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_scanner),
              ),
              onSubmitted: _lookup,
            ),
            const SizedBox(height: 16),
            Expanded(child: _body()),
            const SizedBox(height: 8),
            Text(
              'Checked ${_counts['checked']} of ${_counts['total']}   '
              'Changed ${_counts['changed']}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, color: Colors.red, fontWeight: FontWeight.bold)),
      );
    }
    final t = _tree;
    if (t == null) {
      return const Center(
        child: Text('Scan a tree barcode', style: TextStyle(fontSize: 24, color: Colors.grey)),
      );
    }
    final species = (t['species'] as String?) ?? '';
    final prev = _existing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tree ${t['barcode']}   Plot ${t['plot']}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(species.isEmpty ? 'No species' : species,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
                  if (prev != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Already checked: ${prev['confirmed']}',
                        style: const TextStyle(fontSize: 20, color: Colors.orange),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: species.isEmpty ? null : () => _save(species),
            child: const Text('CORRECT', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 64,
          child: OutlinedButton(
            onPressed: _change,
            child: const Text('CHANGE SPECIES', style: TextStyle(fontSize: 24)),
          ),
        ),
      ],
    );
  }
}
