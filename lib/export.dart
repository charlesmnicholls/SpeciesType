import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'airtable_sync.dart';
import 'db.dart';
import 'format.dart';

class ExportResult {
  final bool ok;
  final String message;
  ExportResult(this.ok, this.message);
}

/// Write all results on the handset to a CSV file and open the Android share sheet
/// (email, Drive, Quick Share, and so on).
class CsvExport {
  static const _header = [
    'Barcode',
    'Plot',
    'Recorded Species',
    'Confirmed Species',
    'Status',
    'Checked At',
    'Checked By',
    'Synced',
  ];

  static String _cell(Object? v) {
    final s = (v ?? '').toString();
    return RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static Future<ExportResult> shareResults() async {
    final rows = await Db.instance.allChecks();
    if (rows.isEmpty) return ExportResult(false, 'No results on this handset.');

    final b = StringBuffer()..writeln(_header.join(','));
    for (final r in rows) {
      b.writeln([
        r['barcode'],
        r['plot'],
        r['recorded'],
        r['confirmed'],
        r['status'],
        formatIso(r['checked_at'] as String?, empty: ''),
        r['handset'],
        r['synced'] == 1 ? 'Yes' : 'No',
      ].map(_cell).join(','));
    }

    final now = DateTime.now();
    final handset = (await Settings.handset).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final name = 'species_check_${handset.isEmpty ? 'handset' : handset}_${fileStamp(now)}.csv';
    final file = File(join((await getTemporaryDirectory()).path, name));
    await file.writeAsString(b.toString());

    final r = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Species Check results $name',
    );
    if (r.status == ShareResultStatus.dismissed) {
      return ExportResult(false, 'Not shared. ${rows.length} results are still on the handset.');
    }
    return ExportResult(true, '${rows.length} results exported to $name');
  }
}
