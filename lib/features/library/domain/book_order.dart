/// Compare digit runs by magnitude without parsing (also handles very long IDs).
int compareBookTitles(String a, String b) {
  final parts = RegExp(r'\d+|\D+');
  final left = parts.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = parts.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    var x = left[i];
    var y = right[i];
    int result;
    if (RegExp(r'^\d').hasMatch(x) && RegExp(r'^\d').hasMatch(y)) {
      x = x.replaceFirst(RegExp(r'^0+'), '');
      y = y.replaceFirst(RegExp(r'^0+'), '');
      result = x.length.compareTo(y.length);
      if (result == 0) result = x.compareTo(y);
    } else {
      result = x.compareTo(y);
    }
    if (result != 0) return result;
  }
  final length = left.length.compareTo(right.length);
  return length != 0 ? length : a.compareTo(b);
}
