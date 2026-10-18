import 'package:intl/intl.dart';

final _db = DateFormat('yyyy-MM-dd');

String dbDate(DateTime d) => _db.format(d);
String shortDate(DateTime d) => DateFormat('d MMM', 'es').format(d);
String longDate(DateTime d) => DateFormat('d MMM y', 'es').format(d);
String rangeLabel(DateTime a, DateTime b) => '${shortDate(a)} – ${longDate(b)}';
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
DateTime today() => DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

/// Acepta "12,50" y "12.50".
double? parseAmount(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
