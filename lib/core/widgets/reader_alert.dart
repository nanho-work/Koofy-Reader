import 'dart:async';
import 'package:flutter/material.dart';
import 'package:koofy_reader/core/localization/app_language.dart';

/// App-owned confirmations, messages and compact menus share this route.
/// OS permission prompts and file pickers remain owned by their SDK/OS.
Future<T?> showReaderDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final queue = _ReaderDialogQueue.instances[navigator] ??= _ReaderDialogQueue(
    navigator,
  );
  return queue.show(context, builder, barrierDismissible);
}

class _ReaderDialogQueue {
  _ReaderDialogQueue(this.navigator);
  final NavigatorState navigator;
  static final instances = Expando<_ReaderDialogQueue>();
  Future<void> _tail = Future.value();

  Future<T?> show<T>(
    BuildContext origin,
    WidgetBuilder builder,
    bool dismissible,
  ) {
    final result = _tail.then<T?>((_) async {
      if (!navigator.mounted || !origin.mounted) return null;
      final route = DialogRoute<T>(
        context: navigator.context,
        themes: InheritedTheme.capture(from: origin, to: navigator.context),
        useSafeArea: true,
        barrierDismissible: dismissible,
        barrierColor: Colors.black.withValues(alpha: .28),
        builder: builder,
      );
      final value = await navigator.push<T>(route);
      // Wait for the closing animation before presenting another alert.
      await route.completed;
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}

class ReaderAlertDialog extends StatelessWidget {
  const ReaderAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  });
  final Widget? title, content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final buttonStyle = TextButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: colors.primary,
      disabledForegroundColor: colors.onSurface.withValues(alpha: .35),
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      textStyle: theme.textTheme.labelLarge!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      elevation: 0,
    );
    final buttons = actions.isEmpty
        ? <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('닫기')),
            ),
          ]
        : actions;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant, width: .7),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null) ...[
                      Semantics(
                        namesRoute: true,
                        header: true,
                        child: DefaultTextStyle(
                          style: theme.textTheme.titleLarge!.copyWith(
                            fontSize: 18,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                          child: title!,
                        ),
                      ),
                      if (content != null) const SizedBox(height: 12),
                    ],
                    if (content != null)
                      DefaultTextStyle(
                        style: theme.textTheme.bodyMedium!.copyWith(
                          fontSize: 14,
                          height: 1.55,
                          color: colors.onSurface,
                        ),
                        child: ListTileTheme(
                          data: ListTileThemeData(
                            contentPadding: EdgeInsets.zero,
                            iconColor: colors.onSurfaceVariant,
                            titleTextStyle: theme.textTheme.bodyLarge,
                            subtitleTextStyle: theme.textTheme.bodySmall,
                          ),
                          child: content!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: .7, color: colors.outlineVariant),
            Theme(
              data: theme.copyWith(
                textButtonTheme: TextButtonThemeData(style: buttonStyle),
                filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: buttonStyle,
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      (MediaQuery.sizeOf(context).height -
                              MediaQuery.viewInsetsOf(context).bottom -
                              48)
                          .clamp(0, double.infinity) *
                      .45,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final vertical =
                          buttons.length > 2 ||
                          MediaQuery.textScalerOf(context).scale(14) / 14 > 1.4;
                      return Flex(
                        direction: vertical ? Axis.vertical : Axis.horizontal,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < buttons.length; i++) ...[
                            if (i > 0)
                              vertical
                                  ? const Divider(height: 1)
                                  : const SizedBox(width: 8),
                            if (vertical)
                              SizedBox(
                                width: double.infinity,
                                child: buttons[i],
                              )
                            else
                              Expanded(child: buttons[i]),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReaderNotice {
  const ReaderNotice({required this.content, this.action, this.title});
  final Widget content;
  final ReaderNoticeAction? action;
  final String? title;
}

class ReaderNoticeAction {
  const ReaderNoticeAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
}

/// Serialize messages per root navigator: an async failure never stacks alerts,
/// and leaving a tab does not lose a completion/undo result.
class ReaderAlerts {
  ReaderAlerts._(this.navigator);
  final NavigatorState navigator;
  static final _instances = Expando<ReaderAlerts>();
  static ReaderAlerts of(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    return _instances[navigator] ??= ReaderAlerts._(navigator);
  }

  final _pending = <String>{};

  Future<void> show(ReaderNotice notice) {
    final identity = notice.content is Text
        ? (notice.content as Text).data
        : null;
    if (identity != null && !_pending.add(identity)) return Future.value();
    if (!navigator.mounted) {
      if (identity != null) _pending.remove(identity);
      return Future.value();
    }
    final next = showReaderDialog<bool>(
      context: navigator.context,
      builder: (context) => ReaderAlertDialog(
        title: Text(notice.title ?? tr('알림')),
        content: notice.content,
        actions: [
          if (notice.action != null)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(notice.action!.label),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('확인')),
          ),
        ],
      ),
    );
    return next
        .then<void>((action) {
          if (action == true) notice.action?.onPressed();
        })
        .catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'reader alerts',
            ),
          );
        })
        .whenComplete(() {
          if (identity != null) _pending.remove(identity);
        });
  }
}
