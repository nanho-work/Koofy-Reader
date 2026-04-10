import 'package:flutter/material.dart';

class ReaderAppBarActions extends StatelessWidget {
  const ReaderAppBarActions({
    super.key,
    required this.hasQueryMatches,
    required this.isCurrentBookmarked,
    required this.onPrevQuery,
    required this.onNextQuery,
    required this.onSearch,
    required this.onToggleBookmark,
    required this.onOpenBookmarks,
    required this.onOpenSettings,
  });

  final bool hasQueryMatches;
  final bool isCurrentBookmarked;
  final VoidCallback onPrevQuery;
  final VoidCallback onNextQuery;
  final VoidCallback onSearch;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasQueryMatches)
          IconButton(
            onPressed: onPrevQuery,
            icon: const Icon(Icons.keyboard_arrow_left),
            tooltip: '이전 검색',
          ),
        if (hasQueryMatches)
          IconButton(
            onPressed: onNextQuery,
            icon: const Icon(Icons.keyboard_arrow_right),
            tooltip: '다음 검색',
          ),
        IconButton(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          tooltip: '검색',
        ),
        IconButton(
          onPressed: onToggleBookmark,
          icon: Icon(
            isCurrentBookmarked ? Icons.bookmark : Icons.bookmark_border,
          ),
          tooltip: '현재 위치 북마크',
        ),
        IconButton(
          onPressed: onOpenBookmarks,
          icon: const Icon(Icons.bookmarks_outlined),
          tooltip: '북마크 목록',
        ),
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.tune),
          tooltip: '읽기 설정',
        ),
      ],
    );
  }
}
