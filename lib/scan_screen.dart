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
  // True when the scanned barcode is not in the tree list. The volunteer then
  // records the species, and the result syncs with Status "New tree".
  bool _isNew = false;
  Map<String, int> _counts = {'total': 0, 'checked': 0, 'changed': 0, 'pending': 0, 'today': 0};
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
    if ((_counts['total'] ?? 0) <= Config.testTrees.length) {
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
      if (await Vibration.hasVibrator()) Vibration.vibrate(duration: 80);
    } catch (_) {}
  }

  Future<void> _lookup(String raw) async {
    final code = raw.replaceAll(RegExp(r'[\r\n\s]'), '');
    // Keep the scanned barcode in the box. Select it all, so the next scan or key
    // press replaces it.
    _ctrl.value = TextEditingValue(
      text: code,
      selection: TextSelection(baseOffset: 0, extentOffset: code.length),
    );
    if (code.isEmpty) {
      _focus.requestFocus();
      return;
    }
    final tree = await Db.instance.getTree(code);
    final existing = await Db.instance.getCheck(code);
    if (!mounted) return;
    await _buzz();
    setState(() {
      _isNew = tree == null;
      _tree = tree ??
          {'barcode': code, 'species': '', 'plot': code.length >= 2 ? code.substring(0, 2) : ''};
      _existing = existing;
    });
  }

  /// Save the result. [dead] = tree is dead or missing; no species is recorded.
  Future<void> _save(String confirmed, {bool dead = false}) async {
    final t = _tree;
    if (t == null) return;
    await Db.instance.saveCheck(
      barcode: t['barcode'] as String,
      plot: (t['plot'] as String?) ?? '',
      recorded: (t['species'] as String?) ?? '',
      confirmed: confirmed,
      handset: await Settings.handset,
      newTree: _isNew,
      status: dead ? Config.statusDeadMissing : null,
    );
    await _buzz();
    if (!mounted) return;
    _ctrl.clear();
    setState(() {
      _tree = null;
      _existing = null;
      _isNew = false;
    });
    await _refreshCounts();
    _snack('Saved: ${dead ? Config.statusDeadMissing : confirmed}');
    _focus.requestFocus();
    if ((_counts['pending'] ?? 0) >= 20 && !_syncing) _sync(quiet: true);
  }

  Future<void> _change() async {
    final current = (_tree?['species'] as String?) ?? '';
    const other = 'Other';
    // Two columns, so all species and "Other" fit on one screen without scrolling.
    Widget tile(BuildContext ctx, String s) => FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: s == current ? null : () => Navigator.pop(ctx, s),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(s, style: const TextStyle(fontSize: 22)),
          ),
        );
    var choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_isNew ? 'Tree species' : 'Correct species',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.6,
                children: [
                  for (final s in Config.species) tile(ctx, s),
                  tile(ctx, other),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == other) choice = await _askOther();
    if (choice != null && choice.isNotEmpty) await _save(choice);
    if (mounted) _focus.requestFocus();
  }

  /// Free text species for "Other". Returns null if the volunteer cancels.
  Future<String?> _askOther() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        void ok() {
          final v = c.text.trim();
          if (v.isNotEmpty) Navigator.pop(ctx, v);
        }

        return AlertDialog(
          title: const Text('Other species'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 22),
            decoration: const InputDecoration(hintText: 'For example: Hazel'),
            onSubmitted: (_) => ok(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: ok, child: const Text('Save')),
          ],
        );
      },
    );
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
            tooltip: 'Sync records',
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
                prefixIcon: BarcodeIcon(),
              ),
              onSubmitted: _lookup,
            ),
            const SizedBox(height: 16),
            Expanded(child: _body()),
            const SizedBox(height: 8),
            Text(
              'Scanned today: ${_counts['today']}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final t = _tree;
    if (t == null) {
      return const Center(
        child: Text('Scan a tree barcode', style: TextStyle(fontSize: 24, color: Colors.grey)),
      );
    }
    final species = (t['species'] as String?) ?? '';
    final prev = _existing;
    // Small screen (Nautiz X41): the species panel takes the free space, and the
    // text scales down to fit it. Buttons have fixed, finger-sized heights.
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final isNew = _isNew;
    // Full barcode is in the scan box. Here: tree number = last 3 digits.
    final code = t['barcode'] as String;
    final treeNo = code.length > 3 ? code.substring(code.length - 3) : code;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tree $treeNo   Plot ${t['plot']}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isNew ? Colors.amber.shade50 : Colors.green.shade50,
              border: Border.all(color: isNew ? Colors.amber.shade300 : Colors.green.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                        isNew
                            ? 'New tree'
                            : species.isEmpty
                                ? 'No species'
                                : species,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (isNew)
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Not in the database. Record the species.',
                        style: TextStyle(fontSize: 18)),
                  ),
                if (prev != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Already checked: ${'${prev['confirmed'] ?? ''}'.isEmpty ? prev['status'] : prev['confirmed']}',
                      style: TextStyle(fontSize: 18, color: Colors.orange.shade800),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Three buttons. The species panel above is Expanded, so it gives up the
        // space for the third button and the screen does not get longer.
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700, shape: buttonShape),
            onPressed: isNew
                ? _change
                : species.isEmpty
                    ? null
                    : () => _save(species),
            child: Text(isNew ? 'RECORD SPECIES' : 'CORRECT',
                style: TextStyle(fontSize: isNew ? 26 : 30, fontWeight: FontWeight.bold)),
          ),
        ),
        if (!isNew) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(shape: buttonShape),
              onPressed: _change,
              child: const Text('CHANGE SPECIES', style: TextStyle(fontSize: 22)),
            ),
          ),
        ],
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: buttonShape,
              foregroundColor: Colors.red.shade800,
              side: BorderSide(color: Colors.red.shade300),
            ),
            onPressed: () => _save('', dead: true),
            child: const Text('DEAD / MISSING', style: TextStyle(fontSize: 22)),
          ),
        ),
      ],
    );
  }
}

/// A plain 1D (linear) barcode icon. Material Icons has only 2D (QR) scanner icons.
class BarcodeIcon extends StatelessWidget {
  const BarcodeIcon({super.key});

  // Bar widths in px; gaps of 2 px between bars.
  static const List<double> _bars = [3, 1, 2, 1, 3, 2, 1, 3, 1, 2];

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      widthFactor: 1,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final w in _bars)
              Container(width: w, height: 24, margin: const EdgeInsets.only(right: 2), color: color),
          ],
        ),
      ),
    );
  }
}
