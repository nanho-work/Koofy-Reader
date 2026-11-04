import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'library_page_test.dart' show pumpLibrary, capture;

void main() {
  testWidgets(
    'async notice waits for an open confirmation instead of stacking',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.instance.initialize();
      await AppLanguage.instance.select('ko');
      late BuildContext origin;
      await pumpLibrary(
        tester,
        rootPage: Scaffold(
          body: Builder(
            builder: (context) {
              origin = context;
              return const Text('library');
            },
          ),
        ),
      );
      showReaderDialog<void>(
        context: origin,
        builder: (context) => ReaderAlertDialog(
          title: const Text('confirm'),
          content: const Text('Keep the current choice.'),
        ),
      );
      await tester.pumpAndSettle();
      ReaderAlerts.of(origin).show(
        ReaderNotice(
          title: tr('새 글 알림'),
          content: Text(tr('알림 연결을 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReaderAlertDialog), findsOneWidget);
      expect(find.text(tr('새 글 알림')), findsNothing);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.text(tr('새 글 알림')), findsOneWidget);
      expect(find.byType(ReaderAlertDialog), findsOneWidget);
      await capture(tester, 'alert-notification');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a queued choice is dropped after its originating page is removed',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      late BuildContext origin;
      await pumpLibrary(
        tester,
        rootPage: Scaffold(
          body: Builder(
            builder: (context) {
              origin = context;
              return const Text('library');
            },
          ),
        ),
      );
      final navigator = Navigator.of(origin);
      late BuildContext transient;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) {
            transient = context;
            return const Scaffold(body: Text('temporary'));
          },
        ),
      );
      await tester.pumpAndSettle();
      ReaderAlerts.of(origin).show(const ReaderNotice(content: Text('first')));
      await tester.pumpAndSettle();
      var built = false;
      final dropped = showReaderDialog<void>(
        context: transient,
        builder: (context) {
          built = true;
          return const ReaderAlertDialog(content: Text('stale choice'));
        },
      );
      navigator.removeRoute(ModalRoute.of(transient)!);
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('확인')));
      await tester.pumpAndSettle();
      await dropped;
      expect(built, isFalse);
      expect(find.byType(ReaderAlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ko', 'en', 'ja']) {
    for (final size in [const Size(320, 700), const Size(700, 320)]) {
      testWidgets(
        'shared alert scrolls long content and large actions $language/$size',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          await AppLanguage.instance.initialize();
          await AppLanguage.instance.select(language);
          addTearDown(() => AppLanguage.instance.select('ko'));
          bool? accepted;
          await pumpLibrary(
            tester,
            size: size,
            scale: 2.5,
            rootPage: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('open'),
                  onPressed: () async {
                    accepted = await showReaderDialog<bool>(
                      context: context,
                      builder: (context) => ReaderAlertDialog(
                        title: Text(tr('새 글 알림')),
                        content: Text(
                          List.filled(
                            20,
                            tr('기기 설정에서 알림을 허용해 주세요.'),
                          ).join('\n'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(tr('취소')),
                          ),
                          FilledButton(
                            key: const ValueKey('accept-alert'),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(tr('확인')),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(find.byType(ReaderAlertDialog), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
          await capture(tester, 'alert-$language-${size.width.toInt()}');
          await tester.ensureVisible(
            find.byKey(const ValueKey('accept-alert')),
          );
          await tester.tap(find.byKey(const ValueKey('accept-alert')));
          await tester.pumpAndSettle();
          expect(accepted, isTrue);
          expect(find.byType(ReaderAlertDialog), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('notices queue without stacking, deduplicate and keep undo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
    await AppLanguage.instance.select('ko');
    late BuildContext origin;
    var undone = 0;
    await pumpLibrary(
      tester,
      rootPage: Scaffold(
        body: Builder(
          builder: (context) {
            origin = context;
            return const Text('library');
          },
        ),
      ),
    );
    final alerts = ReaderAlerts.of(origin);
    alerts.show(
      ReaderNotice(
        content: const Text('first'),
        action: ReaderNoticeAction(label: 'undo', onPressed: () => undone++),
      ),
    );
    alerts.show(const ReaderNotice(content: Text('first')));
    alerts.show(const ReaderNotice(content: Text('second')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderAlertDialog), findsOneWidget);
    expect(find.text('second'), findsNothing);
    await tester.tap(find.text('undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    expect(find.byType(ReaderAlertDialog), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderAlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
