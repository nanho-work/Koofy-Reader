import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_visuals.dart';

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
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          readerContentBottomInset,
        ),
        child: SizedBox.expand(
          child: ClipRect(
            child: text.trim().isEmpty
                ? const SizedBox.shrink()
                : Text(
                    text,
                    style: style,
                    strutStyle: StrutStyle.fromTextStyle(
                      style,
                      forceStrutHeight: true,
                    ),
                    softWrap: true,
                    overflow: TextOverflow.clip,
                  ),
          ),
        ),
      ),
    );
  }
}
