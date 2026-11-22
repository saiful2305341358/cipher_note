/// Small, dependency-free date formatting helpers.
class DateFormatter {
  DateFormatter._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Compact date for note cards: the time for today, "Nov 3" for this
  /// year, otherwise "Nov 3, 2025".
  static String short(DateTime date, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    if (date.year == reference.year &&
        date.month == reference.month &&
        date.day == reference.day) {
      return time(date);
    }
    final monthDay = '${_months[date.month - 1]} ${date.day}';
    if (date.year == reference.year) return monthDay;
    return '$monthDay, ${date.year}';
  }

  /// 24-hour time, e.g. "16:49".
  static String time(DateTime date) =>
      '${_two(date.hour)}:${_two(date.minute)}';

  /// Full date and time, e.g. "Nov 3, 2026, 16:49".
  static String full(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}, ${time(date)}';
}
