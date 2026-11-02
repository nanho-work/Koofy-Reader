import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_order.dart';

class GroupSelection {
  const GroupSelection(this.title, this.ids);
  final String title;
  final List<String> ids;
}

class BookGroupEditor extends StatefulWidget {
  const BookGroupEditor({
    super.key,
    required this.books,
    this.initialIds = const [],
    this.initialTitle = '',
    this.creating = true,
  });
  final List<Book> books;
  final List<String> initialIds;
  final String initialTitle;
  final bool creating;
  @override
  State<BookGroupEditor> createState() => _BookGroupEditorState();
}

class _BookGroupEditorState extends State<BookGroupEditor> {
  late final _name = TextEditingController(text: widget.initialTitle);
  late final _selected = widget.initialIds.toSet().intersection(
    widget.books.map((book) => book.id).toSet(),
  );
  String _query = '';
  bool _descending = false;

  int _compare(Book a, Book b) {
    final comparison = compareBookTitles(a.title, b.title);
    final stable = comparison == 0 ? a.id.compareTo(b.id) : comparison;
    return _descending ? -stable : stable;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final books =
        widget.books
            .where(
              (b) => '${b.title} ${b.author}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
            )
            .toList()
          ..sort(_compare);
    final visibleIds = books.map((book) => book.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty && _selected.containsAll(visibleIds);
    final valid =
        _selected.length >= (widget.creating ? 2 : 1) &&
        (!widget.creating || _name.text.trim().isNotEmpty);
    return DisplayFeatureSubScreen(
      anchorPoint: Offset.zero,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.creating ? tr("책 묶음 만들기") : tr("묶음에 책 추가")),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (widget.creating)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: TextField(
                    controller: _name,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: tr("묶음 이름")),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: tr("책 검색"),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Text(
                widget.creating
                    ? tr("함께 묶을 책을 두 권 이상 선택해 주세요.")
                    : tr("추가할 책을 선택해 주세요."),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text(tr("{0}권 선택", [_selected.length])),
                    PopupMenuButton<bool>(
                      tooltip: tr("책 정렬"),
                      initialValue: _descending,
                      onSelected: (value) =>
                          setState(() => _descending = value),
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(
                          value: false,
                          checked: !_descending,
                          child: Text(tr("제목·회차 오름차순")),
                        ),
                        CheckedPopupMenuItem(
                          value: true,
                          checked: _descending,
                          child: Text(tr("제목·회차 내림차순")),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort, size: 20),
                            const SizedBox(width: 4),
                            Text(tr("정렬")),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: visibleIds.isEmpty
                          ? null
                          : () => setState(() {
                              if (allSelected) {
                                _selected.removeAll(visibleIds);
                              } else {
                                _selected.addAll(visibleIds);
                              }
                            }),
                      child: Text(
                        tr(
                          _query.trim().isEmpty
                              ? (allSelected ? "전체 선택 해제" : "전체 선택")
                              : (allSelected ? "검색 결과 선택 해제" : "검색 결과 전체 선택"),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: books.isEmpty
                    ? Center(child: Text(tr("추가할 수 있는 책이 없습니다.")))
                    : ListView.builder(
                        itemCount: books.length,
                        itemBuilder: (context, i) {
                          final book = books[i];
                          return CheckboxListTile(
                            key: ValueKey('select-${book.id}'),
                            value: _selected.contains(book.id),
                            title: Text(book.title),
                            subtitle: Text(book.author),
                            onChanged: (value) => setState(() {
                              if (value == true) {
                                _selected.add(book.id);
                              } else {
                                _selected.remove(book.id);
                              }
                            }),
                          );
                        },
                      ),
              ),
              Padding(
                padding: AdOverlayInsets.padding(
                  context,
                  const EdgeInsets.all(20),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: valid
                        ? () => Navigator.pop(
                            context,
                            GroupSelection(
                              _name.text.trim(),
                              (widget.books
                                      .where((b) => _selected.contains(b.id))
                                      .toList()
                                    ..sort(_compare))
                                  .map((b) => b.id)
                                  .toList(),
                            ),
                          )
                        : null,
                    child: Text(
                      tr("{0}권 {1}", [
                        _selected.length,
                        widget.creating ? tr('묶기') : tr('추가'),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
