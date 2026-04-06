import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => AssetBookRepository(),
);

final booksProvider = FutureProvider<List<Book>>(
  (ref) => ref.watch(bookRepositoryProvider).getBooks(),
);

abstract class BookRepository {
  Future<List<Book>> getBooks();
  Future<String> readBookContent(Book book);
}

class AssetBookRepository implements BookRepository {
  static const List<Book> _books = [
    Book(
      id: 'sample_1',
      title: '새벽의 쿠피',
      author: 'Koofy Studio',
      assetPath: 'assets/books/sample_1.txt',
      description: '오프라인에서도 바로 열 수 있는 샘플 소설',
    ),
    Book(
      id: 'sample_2',
      title: '리더 빌드 노트',
      author: 'Koofy Team',
      assetPath: 'assets/books/sample_2.txt',
      description: '북리더 MVP 설계와 개발 메모',
    ),
  ];

  @override
  Future<List<Book>> getBooks() async => _books;

  @override
  Future<String> readBookContent(Book book) async {
    return rootBundle.loadString(book.assetPath);
  }
}
