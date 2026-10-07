import 'package:flutter/widgets.dart';

/// Extra scroll reach, not a reserved strip or a smaller page viewport.
class AdOverlayInsets extends InheritedWidget {
  const AdOverlayInsets({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdOverlayInsets>()?.bottom ??
      0;

  static EdgeInsets padding(BuildContext context, EdgeInsets base) =>
      base.copyWith(bottom: base.bottom + bottomOf(context));

  @override
  bool updateShouldNotify(AdOverlayInsets oldWidget) =>
      bottom != oldWidget.bottom;
}
