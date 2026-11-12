String _two(int n) => n.toString().padLeft(2, '0');

/// Local date and time as yyyy-MM-dd HH:mm.
String formatStamp(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
}

/// Local date and time from a stored ISO string. Returns [empty] if there is no value.
String formatIso(String? iso, {String empty = 'Never'}) {
  final t = DateTime.tryParse(iso ?? '');
  return t == null ? empty : formatStamp(t);
}

/// Local date and time for a file name, as yyyyMMdd_HHmm.
String fileStamp(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}_${_two(t.hour)}${_two(t.minute)}';
