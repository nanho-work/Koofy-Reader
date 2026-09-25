import 'package:koofy_reader/features/library/domain/book.dart';

class BookGroup {
  BookGroup({
    required this.id,
    required this.title,
    required List<String> bookIds,
    this.coverPath,
    this.showMemberCovers = false,
  }) : bookIds = List.unmodifiable(bookIds);

  final String id;
  final String title;
  final List<String> bookIds;
  final String? coverPath;
  final bool showMemberCovers;

  BookGroup copyWith({
    String? title,
    List<String>? bookIds,
    String? coverPath,
    bool? showMemberCovers,
  }) => BookGroup(
    id: id,
    title: title ?? this.title,
    bookIds: bookIds ?? this.bookIds,
    coverPath: coverPath ?? this.coverPath,
    showMemberCovers: showMemberCovers ?? this.showMemberCovers,
  );

  // Used only to render a shelf cover; never sent to the reading engine.
  Book get displayBook => Book(
    id: id,
    title: title,
    author: '책 묶음',
    description: '',
    sourceType: BookSourceType.asset,
    coverPath: coverPath,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'bookIds': bookIds,
    'showMemberCovers': showMemberCovers,
  };

  static BookGroup fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final ids = json['bookIds'];
    if (id is! String ||
        !id.startsWith('group_') ||
        title is! String ||
        title.trim().isEmpty ||
        ids is! List ||
        ids.any((id) => id is! String)) {
      throw const FormatException('책 묶음 정보가 손상되었습니다.');
    }
    return BookGroup(
      id: id,
      title: title,
      bookIds: ids.cast<String>(),
      showMemberCovers: json['showMemberCovers'] == true,
    );
  }
}
