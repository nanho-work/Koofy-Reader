import 'dart:convert';

/// The converter and legacy offset migration share the exact same partition.
/// Offsets are UTF-16 code units, as in Dart String and DOM Text.
class TextPublicationMap {
  TextPublicationMap(this.text) {
    var sourceOffset = 0, section = 0, sectionSize = 0;
    for (final line in text.split('\n')) {
      var start = 0;
      do {
        var end = (start + 32000).clamp(0, line.length);
        if (end < line.length &&
            line.codeUnitAt(end - 1) >= 0xd800 &&
            line.codeUnitAt(end - 1) <= 0xdbff) {
          end--;
        }
        final value = line.substring(start, end);
        if (sectionSize > 0 && sectionSize + value.length > 32000) {
          section++;
          sectionSize = 0;
        }
        paragraphs.add(
          TextPublicationParagraph(
            text: value,
            offset: sourceOffset + start,
            section: section,
            index: paragraphs.length,
          ),
        );
        sectionSize += value.length + 1;
        start = end;
      } while (start < line.length);
      sourceOffset += line.length + 1;
    }
  }
  final String text;
  final List<TextPublicationParagraph> paragraphs = [];

  List<List<String>> get sections {
    final result = <List<String>>[];
    for (final p in paragraphs) {
      if (result.length <= p.section) result.add([]);
      result[p.section].add(p.text);
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
      final selector = '#p-${p.index.toString().padLeft(7, '0')}';
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
  });
  final String text;
  final int offset;
  final int section;
  final int index;
}

extension on String {
  int runeAt(int offset) => substring(offset).runes.first;
}
