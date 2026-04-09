import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';

Future<ReaderSettings?> showReaderSettingsSheet({
  required BuildContext context,
  required ReaderSettings initialSettings,
  required double normalFontSize,
  required double largeFontSize,
}) async {
  return showModalBottomSheet<ReaderSettings>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      var draft = initialSettings;
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      choiceChip(
                        ReaderFontOption.sans,
                        draft.fontOption,
                        'Sans',
                        (value) => draft = draft.copyWith(fontOption: value),
                      ),
                      choiceChip(
                        ReaderFontOption.serif,
                        draft.fontOption,
                        'Serif',
                        (value) => draft = draft.copyWith(fontOption: value),
                      ),
                      choiceChip(
                        ReaderFontOption.mono,
                        draft.fontOption,
                        'Mono',
                        (value) => draft = draft.copyWith(fontOption: value),
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
                    min: 1.3,
                    max: 2.2,
                    divisions: 9,
                    onChanged: (value) => setModalState(
                      () => draft = draft.copyWith(lineHeight: value),
                    ),
                  ),
                  sectionTitle('좌우 여백: ${draft.horizontalPadding.round()}'),
                  Slider(
                    value: draft.horizontalPadding,
                    min: 10,
                    max: 34,
                    divisions: 12,
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
