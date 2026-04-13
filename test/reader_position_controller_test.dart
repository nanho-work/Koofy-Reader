import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_position_controller.dart';

void main() {
  group('ReaderPositionController', () {
    test('line start normalization returns beginning of current line', () {
      const content = 'alpha\nbeta\ngamma';

      final result = ReaderPositionController.normalizeToLineStartOffset(
        content: content,
        offset: 8,
      );

      expect(result, 6);
    });

    test('single restore falls back to line start without painter', () {
      const content = 'alpha\nbeta\ngamma';

      final result = ReaderPositionController.normalizeRestoreOffset(
        content: content,
        offset: 8,
        doubleMode: false,
      );

      expect(result, 6);
    });

    test('double restore keeps raw offset when possible', () {
      const content = 'alpha\nbeta\ngamma';

      final result = ReaderPositionController.normalizeRestoreOffset(
        content: content,
        offset: 8,
        doubleMode: true,
      );

      expect(result, 8);
    });
  });
}
