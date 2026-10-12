import 'package:flutter/material.dart';
import 'app_language.dart';

class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppLanguage.instance,
    builder: (context, _) => PopupMenuButton<String>(
      key: const ValueKey('language-picker'),
      tooltip: tr('언어'),
      icon: const Icon(Icons.language),
      initialValue: AppLanguage.instance.selection ?? 'system',
      onSelected: (value) async {
        try {
          await AppLanguage.instance.select(value == 'system' ? null : value);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr('언어를 저장하지 못했습니다. 다시 시도해 주세요.'))),
            );
          }
        }
      },
      itemBuilder: (_) => [
        for (final entry in <String, String>{
          'system': tr('기기 설정 따르기'),
          'ko': '한국어',
          'en': 'English',
          'ja': '日本語',
        }.entries)
          CheckedPopupMenuItem(
            value: entry.key,
            checked: (AppLanguage.instance.selection ?? 'system') == entry.key,
            child: Text(entry.value),
          ),
      ],
    ),
  );
}
