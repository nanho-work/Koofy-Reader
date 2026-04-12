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
          final offset = sorted[index];
          return ListTile(
            title: Text('북마크 ${index + 1}'),
            subtitle: Text('문서 위치: $offset'),
            onTap: () => Navigator.pop(context, sorted[index]),
          );
        },
      );
    },
  );
}

Future<String?> showReaderSearchDialog({
  required BuildContext context,
  required String initialQuery,
  required List<String> history,
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _ReaderSearchDialog(initialQuery: initialQuery, history: history),
  );
}

class _ReaderSearchDialog extends StatefulWidget {
  const _ReaderSearchDialog({
    required this.initialQuery,
    required this.history,
  });

  final String initialQuery;
  final List<String> history;

  @override
  State<_ReaderSearchDialog> createState() => _ReaderSearchDialogState();
}

class _ReaderSearchDialogState extends State<_ReaderSearchDialog> {
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('텍스트 검색'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: '검색어 입력'),
            onChanged: (value) => _query = value,
            onFieldSubmitted: (value) => Navigator.pop(context, value),
          ),
          const SizedBox(height: 12),
          if (widget.history.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.history
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
          onPressed: () => Navigator.pop(context, _query),
          child: const Text('검색'),
        ),
      ],
    );
  }
}
