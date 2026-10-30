import 'package:flutter/material.dart';

/// Shared category/menu emphasis: text only, with no selected background.
TextStyle selectionMenuTextStyle(BuildContext context, bool selected) {
  final theme = Theme.of(context);
  return (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
    fontSize: (theme.textTheme.labelLarge?.fontSize ?? 14) + 1,
    fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
    color: selected
        ? (theme.brightness == Brightness.dark ? Colors.white : Colors.black)
        : theme.colorScheme.onSurfaceVariant,
  );
}

class SelectionMenuChip extends StatelessWidget {
  const SelectionMenuChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => Theme(
    // RawChip creates an opaque Material beneath its transparent Ink layer.
    // Limit the transparent canvas to menu chips, preserving dialogs/cards.
    data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      color: const WidgetStatePropertyAll(Colors.transparent),
      side: BorderSide.none,
      elevation: 0,
      pressElevation: 0,
      surfaceTintColor: Colors.transparent,
      labelStyle: selectionMenuTextStyle(context, selected),
    ),
  );
}

class SelectionMenuButton extends StatelessWidget {
  const SelectionMenuButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: TextButton(
      style: TextButton.styleFrom(
        backgroundColor: Colors.transparent,
        minimumSize: const Size(48, 48),
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: selectionMenuTextStyle(context, selected).color,
        textStyle: selectionMenuTextStyle(context, selected),
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.start),
    ),
  );
}
