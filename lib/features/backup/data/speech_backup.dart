import 'dart:convert';
import 'package:flutter/services.dart';

class SpeechBackup {
  static const channel = MethodChannel('koofy_reader/maintenance');
  Future<Map<String, dynamic>> export() async => Map<String, dynamic>.from(
    await channel.invokeMapMethod<String, dynamic>('exportSpeech') ?? {},
  );
  Future<void> merge(Map<String, dynamic> data) async {
    await channel.invokeMethod<void>('mergeSpeech', data);
  }

  static Map<String, dynamic> validated(Object? raw, Set<String> ids) {
    if (raw == null) return {};
    if (raw is! Map) throw const FormatException('듣기 백업 정보가 올바르지 않습니다.');
    if (raw.isEmpty) return {};
    if (!const ['android', 'ios'].contains(raw['platform']) ||
        raw['settings'] is! Map ||
        raw['positions'] is! Map) {
      throw const FormatException('듣기 백업 형식이 올바르지 않습니다.');
    }
    final settings = Map<String, dynamic>.from(raw['settings'] as Map);
    final speed = settings['speed'],
        voice = settings['voice'],
        follow = settings['follow'],
        alwaysShow = settings['alwaysShow'];
    if (speed != null &&
            (speed is! num || !speed.isFinite || speed < .5 || speed > 2) ||
        voice != null && (voice is! String || voice.length > 1000) ||
        follow != null && follow is! bool ||
        alwaysShow != null && alwaysShow is! bool) {
      throw const FormatException('듣기 설정이 올바르지 않습니다.');
    }
    final positions = <String, String>{};
    for (final entry in (raw['positions'] as Map).entries) {
      if (entry.key is! String || !ids.contains(entry.key)) continue;
      if (entry.value is! String || (entry.value as String).length > 128000) {
        throw const FormatException('듣던 위치가 올바르지 않습니다.');
      }
      final position = jsonDecode(entry.value as String);
      if (position is! Map ||
          position['revision'] is! String ||
          (position['revision'] as String).isEmpty ||
          position['locator'] is! String) {
        throw const FormatException('듣던 위치가 올바르지 않습니다.');
      }
      final locator = jsonDecode(position['locator'] as String);
      if (locator is! Map ||
          locator['href'] is! String ||
          (locator['href'] as String).isEmpty) {
        throw const FormatException('듣던 위치가 올바르지 않습니다.');
      }
      positions[entry.key as String] = entry.value as String;
    }
    return {
      'platform': raw['platform'],
      'settings': {
        if (speed != null) 'speed': speed,
        if (voice != null) 'voice': voice,
        if (follow != null) 'follow': follow,
        if (alwaysShow != null) 'alwaysShow': alwaysShow,
      },
      'positions': positions,
    };
  }
}
