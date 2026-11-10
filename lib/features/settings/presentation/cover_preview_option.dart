import 'package:flutter/material.dart';
import 'settings_choice_option.dart';

class CoverPreviewOption extends StatelessWidget {
  const CoverPreviewOption({
    super.key,
    required this.label,
    required this.showCover,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool showCover;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsChoiceOption(
      label: label,
      selected: selected,
      onTap: onTap,
      preview: SizedBox(
        width: 60,
        height: 86,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: showCover ? colors.primaryContainer : colors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.outline),
          ),
          child: showCover
              ? Icon(Icons.menu_book_outlined, color: colors.primary)
              : Padding(
                  padding: const EdgeInsets.all(9),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final width in [24.0, 37.0, 35.0, 37.0, 27.0])
                        Container(
                          width: width,
                          height: 3,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: colors.onSurfaceVariant.withValues(alpha: .50),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
