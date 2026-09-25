import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/library/domain/book_order.dart';

void main() {
  test(
    'sorts chapters numerically with a deterministic zero-padded tie break',
    () {
      final titles = ['소설 100화', '소설 10화', '소설 2화', '소설 1화', '소설 01화'];
      titles.sort(compareBookTitles);
      expect(titles, ['소설 01화', '소설 1화', '소설 2화', '소설 10화', '소설 100화']);
      expect(compareBookTitles('9' * 40, '1${'0' * 40}'), lessThan(0));
      expect(compareBookTitles('가나다', '가나다'), 0);
    },
  );
}
