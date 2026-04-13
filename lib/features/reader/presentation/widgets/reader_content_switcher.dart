import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_page_pane.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_single_content_list.dart';
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
    required this.spreadScrollController,
    required this.spreadViewportExtent,
    required this.spreadPages,
    required this.isSpreadPaginating,
  });

  final bool doubleMode;
  final String singleContent;
  final TextStyle style;
  final ReaderPalette palette;
  final double horizontalPadding;
  final ScrollController scrollController;
  final ScrollController spreadScrollController;
  final double spreadViewportExtent;
  final PaginatedText? spreadPages;
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

    return ReaderSingleContentList(
      scrollController: scrollController,
      horizontalPadding: horizontalPadding,
      style: style,
      singleContent: singleContent,
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
    final rowCount = (pages.length / 2).ceil();
    final list = ListView.builder(
      controller: spreadScrollController,
      physics: const ClampingScrollPhysics(),
      itemCount: rowCount,
      itemExtent: spreadViewportExtent > 0 ? spreadViewportExtent : null,
      itemBuilder: (context, row) {
        final left = (row * 2).clamp(0, pages.length - 1);
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
      },
    );
    if (!isSpreadPaginating) {
      return list;
    }
    return Stack(
      children: [
        list,
        const Positioned(
          top: 12,
          right: 12,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }
}
