import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'db.dart';

class Settings {
  static Future<String> get pat async =>
      (await Db.instance.getSetting('pat')).replaceAll(RegExp(r'[\r\n\s]'), '');

  static Future<void> setPat(String v) =>
      Db.instance.setSetting('pat', v.replaceAll(RegExp(r'[\r\n\s]'), ''));

  static Future<String> get handset async =>
      (await Db.instance.getSetting('handset')).trim();

  static Future<void> setHandset(String v) =>
      Db.instance.setSetting('handset', v.trim());
}

class SyncResult {
  final bool ok;
  final String message;
  SyncResult(this.ok, this.message);
}

class AirtableSync {
  static Map<String, String> _headers(String pat) => {
        'Authorization': 'Bearer $pat',
        'Content-Type': 'application/json',
      };

  static String _url(String table) =>
      'https://api.airtable.com/v0/${Config.baseId}/${Uri.encodeComponent(table)}';

  /// Send a request. Wait and try again one time if Airtable says "too many requests".
  static Future<http.Response> _send(
      Future<http.Response> Function() call) async {
    var r = await call();
    if (r.statusCode == 429) {
      await Future.delayed(const Duration(seconds: 31));
      r = await call();
    }
    return r;
  }

  static String _text(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is num) return v.toString();
    if (v is Map) return _text(v['text'] ?? v['name'] ?? '');
    if (v is List) return v.isEmpty ? '' : _text(v.first);
    return v.toString().trim();
  }

  static String _clean(String barcode) =>
      barcode.replaceAll(RegExp(r'[\r\n\s]'), '');

  /// Download barcode and species for every tree.
  static Future<SyncResult> downloadSpecies(
      {void Function(int count)? onProgress}) async {
    final pat = await Settings.pat;
    if (pat.isEmpty) return SyncResult(false, 'Enter the Airtable key in Settings.');
    final trees = <Map<String, String>>[];
    String? offset;
    try {
      do {
        final uri = Uri.parse(_url(Config.speciesTable)).replace(
          queryParameters: {
            'pageSize': '100',
            'fields[]': [
              Config.speciesTableBarcodeField,
              Config.speciesTableSpeciesField,
            ],
            if (offset != null) 'offset': offset,
          },
        );
        final r = await _send(() => http.get(uri, headers: _headers(pat)));
        if (r.statusCode != 200) {
          return SyncResult(false, 'Airtable error ${r.statusCode}: ${r.body}');
        }
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        for (final rec in (body['records'] as List)) {
          final f = (rec['fields'] ?? {}) as Map<String, dynamic>;
          final bc = _clean(_text(f[Config.speciesTableBarcodeField]));
          if (bc.isEmpty) continue;
          trees.add({
            'barcode': bc,
            'species': _text(f[Config.speciesTableSpeciesField]),
            'plot': bc.length >= 2 ? bc.substring(0, 2) : '',
          });
        }
        offset = body['offset'] as String?;
        onProgress?.call(trees.length);
      } while (offset != null);
    } catch (e) {
      return SyncResult(false, 'No connection: $e');
    }
    if (trees.isEmpty) {
      return SyncResult(false, 'No trees found. Check the table and field names.');
    }
    await Db.instance.replaceTrees(trees);
    return SyncResult(true, '${trees.length} trees downloaded.');
  }

  static Map<String, dynamic> _fields(Map<String, Object?> c) => {
        Config.fBarcode: c['barcode'],
        Config.fPlot: c['plot'],
        Config.fRecorded: c['recorded'],
        Config.fConfirmed: c['confirmed'],
        Config.fStatus: c['status'],
        Config.fCheckedAt: c['checked_at'],
        Config.fCheckedBy: c['handset'],
      };

  /// Upload all checks that are not yet synced.
  static Future<SyncResult> upload() async {
    final pat = await Settings.pat;
    if (pat.isEmpty) return SyncResult(false, 'Enter the Airtable key in Settings.');
    final pending = await Db.instance.unsyncedChecks();
    if (pending.isEmpty) return SyncResult(true, 'Nothing to send.');
    final fresh = pending.where((c) => c['airtable_id'] == null).toList();
    final again = pending.where((c) => c['airtable_id'] != null).toList();
    var sent = 0;
    try {
      for (var i = 0; i < fresh.length; i += 10) {
        final chunk = fresh.sublist(i, i + 10 > fresh.length ? fresh.length : i + 10);
        final r = await _send(() => http.post(
              Uri.parse(_url(Config.resultsTable)),
              headers: _headers(pat),
              body: jsonEncode({
                'typecast': true,
                'records': [for (final c in chunk) {'fields': _fields(c)}],
              }),
            ));
        if (r.statusCode != 200) {
          return SyncResult(false, 'Airtable error ${r.statusCode}: ${r.body}');
        }
        final recs = (jsonDecode(r.body)['records'] as List);
        for (var j = 0; j < chunk.length; j++) {
          await Db.instance.markSynced(chunk[j]['barcode'] as String, recs[j]['id'] as String);
        }
        sent += chunk.length;
      }
      for (var i = 0; i < again.length; i += 10) {
        final chunk = again.sublist(i, i + 10 > again.length ? again.length : i + 10);
        final r = await _send(() => http.patch(
              Uri.parse(_url(Config.resultsTable)),
              headers: _headers(pat),
              body: jsonEncode({
                'typecast': true,
                'records': [
                  for (final c in chunk) {'id': c['airtable_id'], 'fields': _fields(c)}
                ],
              }),
            ));
        if (r.statusCode != 200) {
          return SyncResult(false, 'Airtable error ${r.statusCode}: ${r.body}');
        }
        for (final c in chunk) {
          await Db.instance.markSynced(c['barcode'] as String, c['airtable_id'] as String);
        }
        sent += chunk.length;
      }
    } catch (e) {
      return SyncResult(false, 'No connection. $sent sent. $e');
    }
    return SyncResult(true, '$sent records sent.');
  }
}
