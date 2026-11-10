import 'package:flutter/material.dart';

class SettingValueTitle extends StatelessWidget {
  const SettingValueTitle({
    super.key,
    required this.title,
    required this.value,
    this.singleLine = false,
  });

  final String title;
  final String value;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = Text(
      title,
      maxLines: singleLine ? 1 : null,
      overflow: singleLine ? TextOverflow.ellipsis : null,
    );
    final valueText = Text(
      value,
      textAlign: TextAlign.end,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (singleLine)
          Expanded(child: titleText)
        else
          Flexible(child: titleText),
        SizedBox(width: singleLine ? 6 : 12),
        if (singleLine) valueText else Flexible(flex: 2, child: valueText),
      ],
    );
  }
}
