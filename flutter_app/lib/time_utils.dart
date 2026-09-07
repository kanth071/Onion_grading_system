/// Relative/short date formatting shared by Dashboard and History -
/// "2 min ago" style for recent items, falling back to a plain date further out.
String relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

String shortDate(DateTime dt) {
  final now = DateTime.now();
  final d = DateTime(dt.year, dt.month, dt.day);
  final today = DateTime(now.year, now.month, now.day);
  final diffDays = today.difference(d).inDays;
  if (diffDays == 0) return 'Today';
  if (diffDays == 1) return 'Yesterday';
  if (diffDays < 7) return '$diffDays days ago';
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

DateTime? tryParseDate(String? iso) {
  if (iso == null) return null;
  return DateTime.tryParse(iso);
}
