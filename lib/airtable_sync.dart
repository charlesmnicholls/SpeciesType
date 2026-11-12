import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'db.dart';

class Settings {
  static Future<String> get pat async =>
      Config.embeddedPat.replaceAll(RegExp(r'[\r\n\s]'), '');

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
  /// Settings keys for the time of the last tree download and the last record sync.
  static const lastDownloadKey = 'last_download';
  static const lastSyncKey = 'last_sync';

  static Future<void> _stampSync() =>
      Db.instance.setSetting(lastSyncKey, DateTime.now().toUtc().toIso8601String());
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
    await Db.instance.setSetting(lastDownloadKey, DateTime.now().toUtc().toIso8601String());
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
    if (pending.isEmpty) return SyncResult(true, 'Nothing to sync.');
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
        await _stampSync();
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
        await _stampSync();
        sent += chunk.length;
      }
    } catch (e) {
      return SyncResult(false, 'No connection. $sent sent. $e');
    }
    return SyncResult(true, '$sent records sent.');
  }

  /// Read-only test of the key, the network and both tables. Returns a debug report.
  /// It does not write to Airtable.
  static Future<SyncResult> testConnection() async {
    final out = StringBuffer();
    var ok = true;
    void line(String s) => out.writeln(s);
    String short(String s) => s.length > 400 ? '${s.substring(0, 400)}...' : s;

    final pat = await Settings.pat;
    line('Base: ${Config.baseId}');
    if (pat.isEmpty) {
      line('Key: MISSING. The APK was built without the AIRTABLE_PAT secret.');
      return SyncResult(false, out.toString());
    }
    line('Key: ${pat.substring(0, pat.length < 3 ? pat.length : 3)}...'
        '${pat.length > 4 ? pat.substring(pat.length - 4) : ''} '
        '(${pat.length} chars${pat.startsWith('pat') ? '' : ', does not start with "pat"'})');

    Future<Map<String, dynamic>?> get(String label, Uri uri) async {
      line('');
      line('== $label');
      line('GET ${uri.path}${uri.hasQuery ? '?${Uri.decodeQueryComponent(uri.query)}' : ''}');
      final sw = Stopwatch()..start();
      try {
        final r = await http
            .get(uri, headers: _headers(pat))
            .timeout(const Duration(seconds: 20));
        line('HTTP ${r.statusCode} in ${sw.elapsedMilliseconds} ms');
        if (r.statusCode != 200) {
          ok = false;
          line(short(r.body));
          if (r.statusCode == 401) line('-> Key is wrong or expired.');
          if (r.statusCode == 403) line('-> Key has no access to this base or table, or the table name is wrong.');
          if (r.statusCode == 404) line('-> Base or table not found. Check the names in config.dart.');
          if (r.statusCode == 422) line('-> A field name in the request is wrong.');
          return null;
        }
        return jsonDecode(r.body) as Map<String, dynamic>;
      } catch (e) {
        ok = false;
        line('FAILED after ${sw.elapsedMilliseconds} ms: $e');
        return null;
      }
    }

    String describe(dynamic v) =>
        v == null ? '(empty)' : '${jsonEncode(v)}  [${v is List ? 'list' : v is Map ? 'object' : v.runtimeType}]';

    // 1. Species table, all fields of one record: shows the real field names and types.
    final species = await get('Read table "${Config.speciesTableName}" (1 record)',
        Uri.parse(_url(Config.speciesTable)).replace(queryParameters: {'pageSize': '1'}));
    if (species != null) {
      final recs = (species['records'] as List?) ?? [];
      if (recs.isEmpty) {
        line('Table is empty.');
      } else {
        final f = (recs.first['fields'] ?? {}) as Map<String, dynamic>;
        line('Fields in first record: ${f.keys.join(', ')}');
        for (final name in [Config.speciesTableBarcodeField, Config.speciesTableSpeciesField]) {
          line('  $name = ${f.containsKey(name) ? describe(f[name]) : 'NOT FOUND (empty or wrong name)'}');
          if (!f.containsKey(name)) ok = false;
        }
        line('  App reads: barcode "${_clean(_text(f[Config.speciesTableBarcodeField]))}", '
            'species "${_text(f[Config.speciesTableSpeciesField])}"');
      }
    }

    // 2. The same query Download trees uses (repeated fields[] keys).
    final dl = await get('Download query (fields filter)',
        Uri.parse(_url(Config.speciesTable)).replace(queryParameters: {
          'pageSize': '1',
          'fields[]': [Config.speciesTableBarcodeField, Config.speciesTableSpeciesField],
        }));
    if (dl != null) {
      final recs = (dl['records'] as List?) ?? [];
      line(recs.isEmpty
          ? 'No records returned.'
          : 'Fields returned: ${((recs.first['fields'] ?? {}) as Map).keys.join(', ')}');
    }

    // 3. Results table: read access and existing field names.
    final res = await get('Read table "${Config.resultsTableName}" (1 record)',
        Uri.parse(_url(Config.resultsTable)).replace(queryParameters: {'pageSize': '1'}));
    if (res != null) {
      final recs = (res['records'] as List?) ?? [];
      line(recs.isEmpty
          ? 'Table found. It has no records yet, so field names cannot be checked.'
          : 'Fields in first record: ${((recs.first['fields'] ?? {}) as Map).keys.join(', ')}');
    }

    line('');
    line(ok ? 'RESULT: OK' : 'RESULT: PROBLEM FOUND (see above)');
    return SyncResult(ok, out.toString());
  }
}
