/// Unified staff display name for the sales app (target/admin surfaces).
///
/// Same resolution order as the admin panel helper: `fullname`, `fullName`,
/// `name`, `displayName` at top level, then the same keys inside `profile`
/// (registration stores the name as `profile.fullname`), falling back to
/// 'بدون اسم' — an explicit badge, never a blank, a UID, or a phone number.
String staffDisplayName(Map<String, dynamic> data) {
  final direct = _pickName(data);
  if (direct.isNotEmpty) return direct;
  final profile = data['profile'];
  if (profile is Map) {
    final nested = _pickName(Map<String, dynamic>.from(profile));
    if (nested.isNotEmpty) return nested;
  }
  return 'بدون اسم';
}

String _pickName(Map<String, dynamic> data) {
  for (final key in ['fullname', 'fullName', 'name', 'displayName']) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}
