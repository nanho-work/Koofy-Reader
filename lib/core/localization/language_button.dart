import 'package:flutter/material.dart';
import 'app_language.dart';

class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.asSettingsTile = false});
  final bool asSettingsTile;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppLanguage.instance,
    builder: (context, _) => PopupMenuButton<String>(
      key: const ValueKey('language-picker'),
      tooltip:
          '${tr('언어')} · ${const {'ko': '한국어', 'en': 'English', 'ja': '日本語'}[AppLanguage.instance.code]}',
      icon: asSettingsTile
          ? null
          : SizedBox(
              width: 32,
              height: 32,
              child: Stack(
                children: [
                  const Positioned(
                    left: 0,
                    top: 0,
                    child: Icon(Icons.language, size: 24),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          AppLanguage.instance.code.toUpperCase(),
                          key: const ValueKey('language-badge'),
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
      child: asSettingsTile
          ? ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language),
              title: Text(tr('언어')),
              subtitle: Text(
                [
                  if (AppLanguage.instance.selection == null) tr('기기 설정 따르기'),
                  const {
                    'ko': '한국어',
                    'en': 'English',
                    'ja': '日本語',
                  }[AppLanguage.instance.code]!,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
            )
          : null,
    ),
  );
}
