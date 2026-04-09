import 'package:flutter/material.dart';

class ReaderBottomPanel extends StatelessWidget {
  const ReaderBottomPanel({
    super.key,
    required this.panelColor,
    required this.displayPage,
    required this.totalPages,
    required this.pageIndex,
    required this.progressRatio,
    required this.controlsExpanded,
    required this.isCurrentBookmarked,
    required this.currentFontSize,
    required this.normalFontSize,
    required this.largeFontSize,
    required this.activeQuery,
    required this.queryCursor,
    required this.queryTotal,
    required this.onPageChanged,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onToggleBookmark,
    required this.onJump,
    required this.onSearch,
    required this.onSetNormalFont,
    required this.onSetLargeFont,
  });

  final Color panelColor;
  final int displayPage;
  final int totalPages;
  final int pageIndex;
  final double progressRatio;
  final bool controlsExpanded;
  final bool isCurrentBookmarked;
  final double currentFontSize;
  final double normalFontSize;
  final double largeFontSize;
  final String activeQuery;
  final int queryCursor;
  final int queryTotal;

  final ValueChanged<int> onPageChanged;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final VoidCallback onToggleBookmark;
  final VoidCallback onJump;
  final VoidCallback onSearch;
  final VoidCallback onSetNormalFont;
  final VoidCallback onSetLargeFont;

  @override
  Widget build(BuildContext context) {
    final pageMax = (totalPages - 1).clamp(0, 1 << 30).toDouble();

    return Container(
      color: panelColor,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  '$displayPage/$totalPages',
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Slider(
                  value: pageIndex.toDouble().clamp(0, pageMax),
                  min: 0,
                  max: pageMax,
                  onChanged: totalPages <= 1
                      ? null
                      : (value) => onPageChanged(value.round()),
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  '${(progressRatio * 100).round()}%',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          if (controlsExpanded)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    onPressed: onPrevPage,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '이전 페이지',
                  ),
                  IconButton(
                    onPressed: onNextPage,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '다음 페이지',
                  ),
                  IconButton(
                    onPressed: onToggleBookmark,
                    icon: Icon(
                      isCurrentBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    tooltip: '북마크',
                  ),
                  IconButton(
                    onPressed: onJump,
                    icon: const Icon(Icons.pin),
                    tooltip: '페이지 이동',
                  ),
                  IconButton(
                    onPressed: onSearch,
                    icon: const Icon(Icons.search),
                    tooltip: '검색',
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('기본'),
                    selected: (currentFontSize - normalFontSize).abs() < 0.01,
                    onSelected: (_) => onSetNormalFont(),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('큰글'),
                    selected: (currentFontSize - largeFontSize).abs() < 0.01,
                    onSelected: (_) => onSetLargeFont(),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          if (activeQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                queryTotal == 0
                    ? '검색어: "$activeQuery" (결과 없음)'
                    : '검색어: "$activeQuery" (${queryCursor + 1}/$queryTotal)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
