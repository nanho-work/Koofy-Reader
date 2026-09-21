import 'dart:convert';

/// The converter and legacy offset migration share the exact same partition.
/// Offsets are UTF-16 code units, as in Dart String and DOM Text.
class TextPublicationMap {
  TextPublicationMap(this.text) {
    final lines = text.split('\n');
    final chapterMode = lines.any(_chapterMarker.hasMatch);
    var sourceOffset = 0, section = 0, sectionSize = 0;
    var hasContent = false;
    for (final line in lines) {
      // A marker must occupy its own line, start in column one and have a title.
      // Indented examples, bare [장], and inline occurrences remain literal.
      final marker = _chapterMarker.firstMatch(line);
      final content = marker == null ? line : marker.group(1)!.trimRight();
      final prefixLength = marker == null
          ? 0
          : line.length - marker.group(1)!.length;
      if (marker != null && !hasContent) {
        // Leading empty lines must not create an empty page before chapter one.
        paragraphs.clear();
        section = 0;
        sectionSize = 0;
      }
      if (content.trim().isNotEmpty) hasContent = true;
      var start = 0;
      do {
        if (chapterMode &&
            (sectionSize >= 32000 ||
                (marker != null &&
                    start == 0 &&
                    sectionSize > 0 &&
                    sectionSize + content.length + 128 > 32000))) {
          // Keep a title with the beginning of its body. For chaptered files,
          // fill the remainder with text instead of stranding a title before
          // a single very long source line. Keep legacy partitioning unchanged.
          section++;
          sectionSize = 0;
        }
        final capacity = chapterMode ? 32000 - sectionSize : 32000;
        var end = (start + capacity).clamp(0, content.length);
        if (end < content.length &&
            content.codeUnitAt(end - 1) >= 0xd800 &&
            content.codeUnitAt(end - 1) <= 0xdbff) {
          end--;
        }
        if (end == start && start < content.length) {
          section++;
          sectionSize = 0;
          continue;
        }
        final value = content.substring(start, end);
        if (sectionSize > 0 && sectionSize + value.length > 32000) {
          section++;
          sectionSize = 0;
        }
        paragraphs.add(
          TextPublicationParagraph(
            text: value,
            offset: sourceOffset + prefixLength + start,
            section: section,
            index: paragraphs.length,
            chapterTitle: start == 0 && marker != null ? content : null,
          ),
        );
        sectionSize += value.length + 1;
        start = end;
      } while (start < content.length);
      sourceOffset += line.length + 1;
    }
  }
  static final _chapterMarker = RegExp(r'^\[장\][ \t]+(\S.*)$');
  final String text;
  final List<TextPublicationParagraph> paragraphs = [];

  bool get hasChapters => paragraphs.any((p) => p.chapterTitle != null);

  List<List<TextPublicationParagraph>> get sections {
    final result = <List<TextPublicationParagraph>>[];
    for (final p in paragraphs) {
      if (result.length <= p.section) result.add([]);
      result[p.section].add(p);
    }
    return result;
  }

  String? locatorAt(int offset) {
    if (offset < 0 || offset >= text.length) return null;
    for (final p in paragraphs) {
      if (p.text.isEmpty || p.offset + p.text.length <= offset) continue;
      var at = (offset - p.offset).clamp(0, p.text.length - 1);
      if (at > 0 &&
          p.text.codeUnitAt(at) >= 0xdc00 &&
          p.text.codeUnitAt(at) <= 0xdfff) {
        at--;
      }
      while (at < p.text.length && p.text[at].trim().isEmpty) {
        at++;
      }
      if (at >= p.text.length) continue;
      final end = at + (p.text.runeAt(at) > 0xffff ? 2 : 1);
      final selector = '#${p.id}';
      return jsonEncode({
        'href': 'EPUB/section-${p.section.toString().padLeft(5, '0')}.xhtml',
        'type': 'application/xhtml+xml',
        'locations': {
          'cssSelector': selector,
          'koofyText': {
            'cssSelector': selector,
            'textNodeIndex': 0,
            'charOffset': at,
          },
          'totalProgression': offset / text.length,
        },
        'text': {
          'before': p.text.substring((at - 48).clamp(0, at), at),
          'highlight': p.text.substring(at, end),
          'after': p.text.substring(end, (end + 48).clamp(end, p.text.length)),
        },
      });
    }
    return null;
  }
}

class TextPublicationParagraph {
  const TextPublicationParagraph({
    required this.text,
    required this.offset,
    required this.section,
    required this.index,
    this.chapterTitle,
  });
  final String text;
  final int offset;
  final int section;
  final int index;
  final String? chapterTitle;

  String get id => 'p-${index.toString().padLeft(7, '0')}';
}

extension on String {
  int runeAt(int offset) => substring(offset).runes.first;
}
