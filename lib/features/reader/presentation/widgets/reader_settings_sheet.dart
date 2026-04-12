import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/data/reader_font_registry.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';

Future<ReaderSettings?> showReaderSettingsSheet({
  required BuildContext context,
  required ReaderSettings initialSettings,
  required double normalFontSize,
  required double largeFontSize,
  required List<ReaderFontItem> fontItems,
}) async {
  return showModalBottomSheet<ReaderSettings>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      var draft = initialSettings;
      var fontExpanded = false;
      return StatefulBuilder(
        builder: (context, setModalState) {
          Widget sectionTitle(String text) {
            return Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Text(text, style: Theme.of(context).textTheme.titleMedium),
            );
          }

          Widget choiceChip<T>(
            T value,
            T selected,
            String label,
            void Function(T) onChanged,
          ) {
            return ChoiceChip(
              label: Text(label),
              selected: value == selected,
              onSelected: (_) => setModalState(() => onChanged(value)),
            );
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionTitle('배경 모드'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      choiceChip(
                        ReaderBackgroundMode.black,
                        draft.backgroundMode,
                        '검정',
                        (value) =>
                            draft = draft.copyWith(backgroundMode: value),
                      ),
                      choiceChip(
                        ReaderBackgroundMode.beige,
                        draft.backgroundMode,
                        '베이지',
                        (value) =>
                            draft = draft.copyWith(backgroundMode: value),
                      ),
                      choiceChip(
                        ReaderBackgroundMode.gray,
                        draft.backgroundMode,
                        '회색',
                        (value) =>
                            draft = draft.copyWith(backgroundMode: value),
                      ),
                    ],
                  ),
                  sectionTitle('글자 크기'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      choiceChip(
                        normalFontSize,
                        draft.fontSize,
                        '기본',
                        (value) => draft = draft.copyWith(fontSize: value),
                      ),
                      choiceChip(
                        largeFontSize,
                        draft.fontSize,
                        '크게',
                        (value) => draft = draft.copyWith(fontSize: value),
                      ),
                    ],
                  ),
                  sectionTitle('폰트'),
                  ExpansionTile(
                    initiallyExpanded: fontExpanded,
                    onExpansionChanged: (value) =>
                        setModalState(() => fontExpanded = value),
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      _selectedFontLabel(
                        selectedKey: draft.fontKey,
                        fontItems: fontItems,
                      ),
                    ),
                    subtitle: const Text('목록에서 글꼴을 선택하세요'),
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math
                              .min(280.0, fontItems.length * 64.0)
                              .toDouble(),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: fontItems
                              .map(
                                (font) => ListTile(
                                  onTap: () => setModalState(
                                    () => draft = draft.copyWith(
                                      fontKey: font.key,
                                    ),
                                  ),
                                  leading: Icon(
                                    draft.fontKey == font.key
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                  ),
                                  title: Text(
                                    font.label,
                                    style: TextStyle(
                                      fontFamily: font.previewFamily,
                                    ),
                                  ),
                                  subtitle: font.isCustom
                                      ? const Text('추가한 폰트')
                                      : const Text('기본 폰트'),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                  sectionTitle('레이아웃'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      choiceChip(
                        ReaderPageLayoutMode.auto,
                        draft.pageLayoutMode,
                        '자동',
                        (value) =>
                            draft = draft.copyWith(pageLayoutMode: value),
                      ),
                      choiceChip(
                        ReaderPageLayoutMode.single,
                        draft.pageLayoutMode,
                        '1페이지',
                        (value) =>
                            draft = draft.copyWith(pageLayoutMode: value),
                      ),
                      choiceChip(
                        ReaderPageLayoutMode.double,
                        draft.pageLayoutMode,
                        '2페이지',
                        (value) =>
                            draft = draft.copyWith(pageLayoutMode: value),
                      ),
                    ],
                  ),
                  sectionTitle('줄 간격: ${draft.lineHeight.toStringAsFixed(2)}'),
                  Slider(
                    value: draft.lineHeight,
                    min: 1.1,
                    max: 2.8,
                    divisions: 17,
                    onChanged: (value) => setModalState(
                      () => draft = draft.copyWith(lineHeight: value),
                    ),
                  ),
                  sectionTitle('좌우 여백: ${draft.horizontalPadding.round()}'),
                  Slider(
                    value: draft.horizontalPadding,
                    min: 0,
                    max: 64,
                    divisions: 32,
                    onChanged: (value) => setModalState(
                      () => draft = draft.copyWith(horizontalPadding: value),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('화면 꺼짐 방지'),
                    value: draft.keepScreenOn,
                    onChanged: (value) => setModalState(
                      () => draft = draft.copyWith(keepScreenOn: value),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, draft),
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _selectedFontLabel({
  required String selectedKey,
  required List<ReaderFontItem> fontItems,
}) {
  for (final item in fontItems) {
    if (item.key == selectedKey) {
      return item.label;
    }
  }
  if (fontItems.isNotEmpty) {
    return fontItems.first.label;
  }
  return '기본 Sans';
}
