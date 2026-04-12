import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_page_pane.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_visuals.dart';

class ReaderContentSwitcher extends StatelessWidget {
  const ReaderContentSwitcher({
    super.key,
    required this.doubleMode,
    required this.singleContent,
    required this.style,
    required this.palette,
    required this.horizontalPadding,
    required this.scrollController,
    required this.spreadPages,
    required this.spreadIndex,
    required this.isSpreadPaginating,
  });

  final bool doubleMode;
  final String singleContent;
  final TextStyle style;
  final ReaderPalette palette;
  final double horizontalPadding;
  final ScrollController scrollController;
  final PaginatedText? spreadPages;
  final int spreadIndex;
  final bool isSpreadPaginating;

  @override
  Widget build(BuildContext context) {
    if (doubleMode) {
      return _buildSpreadBody();
    }
    return _buildSingleBody();
  }

  Widget _buildSingleBody() {
    if (singleContent.trim().isEmpty) {
      return ReaderPagePane(
        text: '',
        style: style,
        backgroundColor: palette.background,
        horizontalPadding: horizontalPadding,
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: readerVerticalPadding),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            readerContentBottomInset,
          ),
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

  Widget _buildSpreadBody() {
    final pages = spreadPages;
    if (pages == null || pages.length == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: readerVerticalPadding),
        child: Row(
          children: [
            Expanded(
              child: ReaderPagePane(
                text: '',
                style: style,
                backgroundColor: palette.background,
                horizontalPadding: horizontalPadding,
              ),
            ),
            Container(
              width: readerDoublePageGap,
              color: palette.background,
              alignment: Alignment.center,
              child: Container(width: 1, color: palette.divider),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ReaderPagePane(
                    text: '',
                    style: style,
                    backgroundColor: palette.background,
                    horizontalPadding: horizontalPadding,
                  ),
                  if (isSpreadPaginating)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final left = spreadIndex.clamp(0, pages.length - 1);
    final right = left + 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: readerVerticalPadding),
      child: Row(
        children: [
          Expanded(
            child: ReaderPagePane(
              text: pages[left],
              style: style,
              backgroundColor: palette.background,
              horizontalPadding: horizontalPadding,
            ),
          ),
          Container(
            width: readerDoublePageGap,
            color: palette.background,
            alignment: Alignment.center,
            child: Container(width: 1, color: palette.divider),
          ),
          Expanded(
            child: right < pages.length
                ? ReaderPagePane(
                    text: pages[right],
                    style: style,
                    backgroundColor: palette.background,
                    horizontalPadding: horizontalPadding,
                  )
                : ReaderPagePane(
                    text: '',
                    style: style,
                    backgroundColor: palette.background,
                    horizontalPadding: horizontalPadding,
                  ),
          ),
        ],
      ),
    );
  }
}
