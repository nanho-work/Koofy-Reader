import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:koofy_reader/core/storage/library_mutations.dart';

/// Content-addressed private files; the native readers consume this same catalog.
class PersonalFontStore {
  PersonalFontStore(this.directory);
  final Directory directory;
  static const maxBytes = 10 * 1024 * 1024;
  static const maxFonts = 50;

  static String validate(Uint8List bytes) {
    if (bytes.length < 12 || bytes.length > maxBytes) {
      throw const FormatException('글꼴 파일은 10MB 이하여야 합니다.');
    }
    final data = ByteData.sublistView(bytes);
    final signature = data.getUint32(0);
    if (signature != 0x4f54544f && signature != 0x00010000) {
      throw const FormatException('TTF 또는 OTF 글꼴 파일을 선택해 주세요.');
    }
    final count = data.getUint16(4);
    if (count == 0 || count > 256 || 12 + count * 16 > bytes.length) {
      throw const FormatException('손상된 글꼴 파일입니다.');
    }
    final tags = <String>{};
    for (var i = 0; i < count; i++) {
      final at = 12 + i * 16;
      final offset = data.getUint32(at + 8), length = data.getUint32(at + 12);
      if (offset < 12 + count * 16 || offset + length > bytes.length) {
        throw const FormatException('글꼴 내부 데이터가 올바르지 않습니다.');
      }
      tags.add(String.fromCharCodes(bytes.sublist(at, at + 4)));
    }
    if (!tags.containsAll({'cmap', 'head', 'name'})) {
      throw const FormatException('필수 글꼴 정보가 없습니다.');
    }
    return signature == 0x4f54544f ? 'otf' : 'ttf';
  }

  Future<List<Map<String, dynamic>>> load() async {
    final file = File('${directory.path}/catalog.json');
    if (!await file.exists()) return [];
    if (await file.length() > 1024 * 1024) {
      throw const FormatException('글꼴 목록이 너무 큽니다.');
    }
    final json = jsonDecode(await file.readAsString()) as Map;
    if (json['version'] != 1) throw const FormatException('지원하지 않는 글꼴 목록입니다.');
    return (json['families'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  File fileFor(Map<String, dynamic> family) {
    final name = (family['faces'] as List).first['file'] as String;
    if (!RegExp(r'^[a-f0-9]{64}\.(otf|ttf)$').hasMatch(name)) {
      throw const FormatException('글꼴 경로가 올바르지 않습니다.');
    }
    return File('${directory.path}/$name');
  }

  Future<void> _save(List<Map<String, dynamic>> families) async {
    await directory.create(recursive: true);
    final temporary = File('${directory.path}/catalog.json.part');
    await temporary.writeAsString(
      jsonEncode({'version': 1, 'families': families}),
      flush: true,
    );
    await temporary.rename('${directory.path}/catalog.json');
  }

  Future<String> install(Uint8List bytes, String name) => LibraryMutations.run(
    () async {
      final extension = validate(bytes);
      final hash = sha256.convert(bytes).toString(),
          id = 'personal_${sha256.convert(bytes).toString().substring(0, 32)}';
      final families = await load();
      if (families.any((f) => f['id'] == id)) return id;
      if (families.length >= maxFonts) {
        throw const FormatException('내 글꼴은 최대 50개까지 보관할 수 있습니다.');
      }
      var label = name
          .split(RegExp(r'[/\\]'))
          .last
          .replaceFirst(RegExp(r'\.(otf|ttf)$', caseSensitive: false), '')
          .trim();
      if (label.isEmpty) label = '내 글꼴';
      if (label.length > 120) label = label.substring(0, 120);
      await directory.create(recursive: true);
      final file = File('${directory.path}/$hash.$extension');
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      families.add({
        'id': id,
        'label': label,
        'cssFamily': 'KoofyPersonal_${hash.substring(0, 32)}',
        'faces': [
          {'file': '$hash.$extension', 'weight': 400, 'sha256': hash},
        ],
      });
      await _save(families);
      return id;
    },
  );

  Future<void> remove(String id) => LibraryMutations.run(() async {
    final families = await load();
    final removed = families.where((f) => f['id'] == id).toList();
    await _save(families.where((f) => f['id'] != id).toList());
    for (final family in removed) {
      final file = fileFor(family);
      if (await file.exists()) await file.delete();
    }
  });
}
