import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';

/// Strict conversion only. The UI must show a preview and get confirmation.
class LegacyTextImport {
  static Future<Uint8List>? _table;
  static Future<String> preview(String path) async {
    final file = File(path);
    final length = await file.length();
    if (length <= 0 || length > AppConstants.maxTxtBytes) {
      throw const FormatException('20MB 이하의 TXT를 선택해 주세요.');
    }
    final bytes = await file.readAsBytes();
    final table = await (_table ??= rootBundle
        .load('assets/encoding/cp949.bin')
        .then((b) => b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes)));
    return Isolate.run(() => decode(bytes, table));
  }

  static String decode(Uint8List bytes, Uint8List table) {
    final pairs = ByteData.sublistView(table);
    final map = <int, int>{};
    for (var i = 0; i < table.length; i += 4) {
      map[pairs.getUint16(i)] = pairs.getUint16(i + 2);
    }
    final result = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      final first = bytes[i];
      if (first < 0x80) {
        if (first < 0x20 && first != 9 && first != 10 && first != 13) {
          throw const FormatException('텍스트가 아닌 데이터가 포함되어 있습니다.');
        }
        result.add(first);
      } else {
        if (++i >= bytes.length) throw const FormatException('문자 데이터가 잘렸습니다.');
        final code = map[(first << 8) | bytes[i]];
        if (code == null) {
          throw const FormatException('CP949/EUC-KR로 읽을 수 없는 문자입니다.');
        }
        result.add(code);
      }
    }
    final text = String.fromCharCodes(result);
    if (utf8.encode(text).length > AppConstants.maxTxtBytes) {
      throw const FormatException('UTF-8 변환 결과가 20MB를 초과합니다.');
    }
    return text;
  }
}
