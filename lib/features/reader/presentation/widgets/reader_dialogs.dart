import 'package:flutter/material.dart';

Future<int?> showReaderBookmarksSheet({
  required BuildContext context,
  required Set<int> bookmarks,
}) {
  final sorted = bookmarks.toList()..sort();
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return ListView.separated(
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final page = sorted[index] + 1;
          return ListTile(
            title: Text('$page 페이지'),
            onTap: () => Navigator.pop(context, sorted[index]),
          );
        },
      );
    },
  );
}

Future<int?> showReaderPageJumpDialog({
  required BuildContext context,
  required int totalPages,
  required int currentPage,
}) async {
  final controller = TextEditingController(text: currentPage.toString());
  try {
    return await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('페이지 이동'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: '1 ~ $totalPages'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final page = int.tryParse(controller.text.trim());
                Navigator.pop(context, page);
              },
              child: const Text('이동'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

Future<String?> showReaderSearchDialog({
  required BuildContext context,
  required String initialQuery,
  required List<String> history,
}) async {
  final controller = TextEditingController(text: initialQuery);
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('텍스트 검색'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: '검색어 입력'),
                onSubmitted: (value) => Navigator.pop(context, value),
              ),
              const SizedBox(height: 12),
              if (history.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: history
                      .take(6)
                      .map(
                        (item) => ActionChip(
                          label: Text(item),
                          onPressed: () => Navigator.pop(context, item),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('초기화'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('검색'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
