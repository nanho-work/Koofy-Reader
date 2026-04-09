import 'package:flutter/material.dart';

class ReaderPagePane extends StatelessWidget {
  const ReaderPagePane({
    super.key,
    required this.text,
    required this.style,
    required this.backgroundColor,
    required this.horizontalPadding,
  });

  final String text;
  final TextStyle style;
  final Color backgroundColor;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      alignment: Alignment.topLeft,
      child: text.trim().isEmpty
          ? const SizedBox.shrink()
          : SelectableText(text, style: style),
    );
  }
}
