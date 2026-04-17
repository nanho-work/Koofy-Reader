import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/application/controllers/reader_navigation_controller.dart';

void main() {
  const controller = ReaderNavigationController();

  test('single mode resolves left tap to previous', () {
    expect(
      controller.resolveTapCommand(
        dx: 40,
        width: 300,
        doubleMode: false,
        isSpreadPaginating: false,
        isSpreadJumping: false,
        isDoubleViewportSettling: false,
      ),
      ReaderNavigationCommand.singlePrevious,
    );
  });

  test('single mode resolves right tap to next', () {
    expect(
      controller.resolveTapCommand(
        dx: 260,
        width: 300,
        doubleMode: false,
        isSpreadPaginating: false,
        isSpreadJumping: false,
        isDoubleViewportSettling: false,
      ),
      ReaderNavigationCommand.singleNext,
    );
  });

  test('double mode resolves left tap to previous spread', () {
    expect(
      controller.resolveTapCommand(
        dx: 40,
        width: 300,
        doubleMode: true,
        isSpreadPaginating: false,
        isSpreadJumping: false,
        isDoubleViewportSettling: false,
      ),
      ReaderNavigationCommand.doublePrevious,
    );
  });

  test('double mode blocks tap navigation while spread is unstable', () {
    expect(
      controller.resolveTapCommand(
        dx: 260,
        width: 300,
        doubleMode: true,
        isSpreadPaginating: true,
        isSpreadJumping: false,
        isDoubleViewportSettling: false,
      ),
      ReaderNavigationCommand.none,
    );
  });
}
