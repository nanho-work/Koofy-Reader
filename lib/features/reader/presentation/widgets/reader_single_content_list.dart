import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_visuals.dart';

class ReaderSingleContentList extends StatelessWidget {
  const ReaderSingleContentList({
    super.key,
    required this.scrollController,
    required this.horizontalPadding,
    required this.style,
    required this.singleContent,
  });

  final ScrollController scrollController;
  final double horizontalPadding;
  final TextStyle style;
  final String singleContent;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        readerVerticalPadding,
        horizontalPadding,
        readerContentBottomInset,
      ),
      child: RepaintBoundary(
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            singleContent,
            style: style,
            strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
            softWrap: true,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    );
  }
}
