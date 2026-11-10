import 'package:flutter/material.dart';

class SettingsChoiceOption extends StatelessWidget {
  const SettingsChoiceOption({
    super.key,
    required this.label,
    this.preview,
    required this.selected,
    this.onTap,
  });

  final String label;
  final Widget? preview;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final border = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: selected
          ? const BorderSide(color: Color(0xFF82B947), width: 2)
          : BorderSide(color: colors.outlineVariant),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                colors.primary.withValues(alpha: .16),
                colors.surface,
              )
            : colors.surface,
        shape: border,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (preview case final preview?) ...[
                        Center(child: ExcludeSemantics(child: preview)),
                        const SizedBox(height: 8),
                      ],
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: preview == null ? 16 : 0,
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  if (selected)
                    Positioned.fill(
                      child: Align(
                        alignment: preview == null
                            ? AlignmentDirectional.centerEnd
                            : AlignmentDirectional.topEnd,
                        child: Icon(
                          Icons.check_circle,
                          size: 16,
                          color: colors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
