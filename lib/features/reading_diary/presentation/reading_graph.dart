import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:koofy_reader/core/localization/app_language.dart';
import '../data/reading_diary.dart';
import 'diary_format.dart';
import 'diary_style.dart';

class ReadingGraph extends StatefulWidget {
  const ReadingGraph({
    super.key,
    required this.month,
    required this.days,
    required this.monthly,
    required this.onMonthlyChanged,
    required this.onDay,
    required this.onMonth,
  });
  final DateTime month;
  final List<DiaryDay> days;
  final bool monthly;
  final ValueChanged<bool> onMonthlyChanged;
  final ValueChanged<DiaryDay> onDay;
  final ValueChanged<DateTime> onMonth;
  @override
  State<ReadingGraph> createState() => _ReadingGraphState();
}

class _ReadingGraphState extends State<ReadingGraph> {
  final _transform = TransformationController();
  int? _selected;
  @override
  void didUpdateWidget(covariant ReadingGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month ||
        oldWidget.monthly != widget.monthly) {
      _selected = null;
      _transform.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final value = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      4.0,
    );
    _transform.value = Matrix4.diagonal3Values(value, value, 1);
  }

  void _selectPoint(Offset point, double width, int count) {
    final index = (((point.dx - 48) / (width - 64)) * (count - 1))
        .round()
        .clamp(0, count - 1);
    if (_selected != index) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.monthly
        ? 12
        : DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final values = List.filled(count, 0);
    for (final day in widget.days) {
      final date = DateTime.parse(day.date);
      if (date.year == widget.month.year &&
          (widget.monthly || date.month == widget.month.month)) {
        values[widget.monthly ? date.month - 1 : date.day - 1] +=
            day.duration.inMilliseconds;
      }
    }
    final total = Duration(milliseconds: values.fold(0, (a, b) => a + b));
    final selected = _selected;
    final selectionDate = selected == null
        ? null
        : DateTime(
            widget.month.year,
            widget.monthly ? selected + 1 : widget.month.month,
            widget.monthly ? 1 : selected + 1,
          );
    final day = selectionDate == null
        ? null
        : widget.days
              .where((d) => d.date == diaryDate(selectionDate))
              .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SizedBox(
          height: math.max(
            constraints.maxHeight,
            360 + 60 * (MediaQuery.textScalerOf(context).scale(12) / 12 - 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: DiaryStyle.green.withValues(alpha: .055),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Wrap(
                      children: [
                        for (final monthly in [false, true])
                          Padding(
                            padding: const EdgeInsets.all(3),
                            child: Semantics(
                              selected: widget.monthly == monthly,
                              child: TextButton(
                                onPressed: () =>
                                    widget.onMonthlyChanged(monthly),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(58, 38),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  foregroundColor: widget.monthly == monthly
                                      ? DiaryStyle.ink
                                      : DiaryStyle.muted,
                                  backgroundColor: widget.monthly == monthly
                                      ? Theme.of(context).colorScheme.surface
                                      : Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                ),
                                child: Text(
                                  tr(monthly ? '월별' : '일별'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: widget.monthly == monthly
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DiaryToolButton(
                        label: tr('축소'),
                        icon: Icons.remove_rounded,
                        onPressed: () => _zoom(1 / 1.5),
                      ),
                      DiaryToolButton(
                        label: tr('확대'),
                        icon: Icons.add_rounded,
                        onPressed: () => _zoom(1.5),
                      ),
                      DiaryToolButton(
                        label: tr('전체 보기'),
                        icon: Icons.fit_screen_rounded,
                        onPressed: () => _transform.value = Matrix4.identity(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  tr('독서 시간'),
                  style: const TextStyle(fontSize: 12, color: DiaryStyle.muted),
                ),
              ),
              const SizedBox(height: 5),
              Center(
                child: Text(
                  diaryTime(total),
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.8,
                    color: DiaryStyle.ink,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => ClipRect(
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 4,
                      panEnabled: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _selectPoint(
                          details.localPosition,
                          c.maxWidth,
                          count,
                        ),
                        onLongPressStart: (details) => _selectPoint(
                          details.localPosition,
                          c.maxWidth,
                          count,
                        ),
                        onLongPressMoveUpdate: (details) => _selectPoint(
                          details.localPosition,
                          c.maxWidth,
                          count,
                        ),
                        child: CustomPaint(
                          key: const ValueKey('reading-line-chart'),
                          size: Size(c.maxWidth, c.maxHeight),
                          painter: _LinePainter(
                            values: values,
                            selected: selected,
                            color: DiaryStyle.green,
                            foreground: DiaryStyle.ink,
                            language: AppLanguage.instance.code,
                            monthly: widget.monthly,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 72,
                child: Center(
                  child: selected == null
                      ? Text(
                          tr('그래프를 누르면 기록을 볼 수 있어요'),
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : TextButton(
                          onPressed: values[selected] <= 0
                              ? null
                              : () => widget.monthly
                                    ? widget.onMonth(selectionDate!)
                                    : day == null
                                    ? null
                                    : widget.onDay(day),
                          child: Text(
                            '${DateFormat(widget.monthly ? 'yMMMM' : 'yMMMd', AppLanguage.instance.code).format(selectionDate!)} · ${diaryTime(Duration(milliseconds: values[selected]))}',
                            textAlign: TextAlign.center,
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

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.selected,
    required this.color,
    required this.foreground,
    required this.language,
    required this.monthly,
  });
  final List<int> values;
  final int? selected;
  final Color color, foreground;
  final String language;
  final bool monthly;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 80 || size.height < 60) return;
    final rect = Rect.fromLTRB(48, 16, size.width - 16, size.height - 32);
    final peakMinutes = math.max(1, values.reduce(math.max) / 60000);
    final step = peakMinutes <= 20
        ? 5.0
        : peakMinutes <= 60
        ? 15.0
        : peakMinutes <= 120
        ? 30.0
        : 60.0;
    final maximum = (peakMinutes / (step * 4)).ceil() * step * 4 * 60000;
    void label(String text, Offset point, {bool centered = false}) {
      final p = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 10,
            fontFamily: 'Roboto',
            color: foreground.withValues(alpha: .65),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, point - Offset(centered ? p.width / 2 : 0, 0));
      p.dispose();
    }

    for (var i = 0; i < 5; i++) {
      final y = rect.bottom - rect.height * i / 4;
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        Paint()..color = foreground.withValues(alpha: .08),
      );
      final minutes = (maximum * i / 4 / 60000).round();
      label(
        minutes >= 60 ? '${(minutes / 60).toStringAsFixed(1)}h' : '${minutes}m',
        Offset(0, y - 6),
      );
    }
    Offset point(int i) => Offset(
      rect.left + rect.width * i / (values.length - 1),
      rect.bottom - rect.height * values[i] / maximum,
    );
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .055), color.withValues(alpha: .0)],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < values.length; i++) {
      if (values[i] > 0) {
        canvas.drawCircle(
          point(i),
          i == selected ? 5 : 1.8,
          Paint()..color = color,
        );
      }
      if (i == selected ||
          i == 0 ||
          i == values.length - 1 ||
          (monthly ? i % 2 == 0 : i % 5 == 4)) {
        label(
          '${i + 1}',
          Offset(point(i).dx, rect.bottom + 10),
          centered: true,
        );
      }
    }
    if (selected != null) {
      final p = point(selected!);
      canvas.drawLine(
        Offset(p.dx, rect.top),
        Offset(p.dx, rect.bottom),
        Paint()
          ..color = color.withValues(alpha: .25)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5, Paint()..color = color);
      final text = TextPainter(
        text: TextSpan(
          text: diaryTime(Duration(milliseconds: values[selected!])),
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: DiaryStyle.ink,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(60, size.width - 32));
      final x = (p.dx - text.width / 2 - 9)
          .clamp(8.0, math.max(8.0, size.width - text.width - 26))
          .toDouble();
      final y = math.max(0.0, p.dy - text.height - 26);
      final bubble = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, text.width + 18, text.height + 12),
        const Radius.circular(7),
      );
      canvas.drawRRect(bubble, Paint()..color = const Color(0xFFF5F5EF));
      canvas.drawRRect(
        bubble,
        Paint()
          ..color = DiaryStyle.rule
          ..style = PaintingStyle.stroke,
      );
      text.paint(canvas, Offset(x + 9, y + 6));
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}
