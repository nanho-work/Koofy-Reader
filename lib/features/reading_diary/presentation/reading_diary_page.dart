import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/core/widgets/book_shelf_layout.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/presentation/widgets/book_tile.dart';
import '../data/reading_diary.dart';
import 'diary_format.dart';
import 'reading_graph.dart';
import 'diary_style.dart';

class ReadingDiaryPage extends ConsumerStatefulWidget {
  const ReadingDiaryPage({super.key, this.now});
  final DateTime? now;
  @override
  ConsumerState<ReadingDiaryPage> createState() => _ReadingDiaryPageState();
}

class _ReadingDiaryPageState extends ConsumerState<ReadingDiaryPage>
    with WidgetsBindingObserver {
  late DateTime _month;
  List<DiaryDay> _days = [];
  ReadingDiary? _diary;
  bool _graph = false;
  bool _monthly = false;
  bool _loading = true;
  String? _selectedDay;
  Object? _error;
  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _earliest => _days.isEmpty
      ? DateTime(_now.year, _now.month)
      : DateTime.parse('${_days.first.date.substring(0, 7)}-01');
  DateTime get _latest => DateTime(_now.year, _now.month + 1);
  @override
  void initState() {
    super.initState();
    _month = DateTime(_now.year, _now.month);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_diary == null) {
      _diary = ref.read(readingDiaryProvider);
      _diary!.addListener(_reload);
      _reload();
    }
  }

  Future<void> _reload() async {
    try {
      final days = await _diary!.load();
      if (mounted) {
        setState(() {
          _days = days;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _diary?.removeListener(_reload);
    super.dispose();
  }

  void _move(int direction) => setState(() {
    _month = _graph && _monthly
        ? DateTime(_month.year + direction, _month.month)
        : DateTime(_month.year, _month.month + direction);
    if (_month.isBefore(_earliest)) _month = _earliest;
    if (_month.isAfter(_latest)) _month = _latest;
  });
  Future<void> _chooseMonth() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: _earliest,
      lastDate: DateTime(_latest.year, _latest.month + 1, 0),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (chosen != null && mounted) {
      setState(() => _month = DateTime(chosen.year, chosen.month));
    }
  }

  void _showDay(DiaryDay day) {
    setState(() => _selectedDay = day.date);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DiaryDayPage(day: day)));
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final annual = _graph && _monthly;
    final canPrevious = annual
        ? _month.year > _earliest.year
        : _month.isAfter(_earliest);
    final canNext = annual
        ? _month.year < _latest.year
        : _month.isBefore(_latest);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DiaryStyle.maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 28,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: SizedBox(
                      height:
                          76 *
                          (MediaQuery.textScalerOf(context).scale(12) / 12)
                              .clamp(1, 2.0),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                DiaryToolButton(
                                  label: tr('이전'),
                                  icon: Icons.chevron_left_rounded,
                                  onPressed: canPrevious
                                      ? () => _move(-1)
                                      : null,
                                ),
                                Flexible(
                                  child: Semantics(
                                    button: true,
                                    label: DateFormat.yMMMM(
                                      AppLanguage.instance.code,
                                    ).format(_month),
                                    child: TextButton(
                                      onPressed: _chooseMonth,
                                      style: TextButton.styleFrom(
                                        foregroundColor: DiaryStyle.ink,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            annual
                                                ? tr('기록')
                                                : '${_month.year}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.1,
                                              fontWeight: FontWeight.w500,
                                              color: DiaryStyle.muted,
                                              letterSpacing: .5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            annual
                                                ? '${_month.year}'
                                                : DateFormat.MMMM(
                                                    AppLanguage.instance.code,
                                                  ).format(_month),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 26,
                                              height: 1.15,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -.7,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                DiaryToolButton(
                                  label: tr('다음'),
                                  icon: Icons.chevron_right_rounded,
                                  onPressed: canNext ? () => _move(1) : null,
                                ),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: DiaryToolButton(
                              label: tr(_graph ? '달력 보기' : '그래프 보기'),
                              icon: _graph
                                  ? Icons.calendar_month_outlined
                                  : Icons.show_chart_rounded,
                              onPressed: () => setState(() => _graph = !_graph),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_loading)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tr('독서 기록을 불러오지 못했습니다.')),
                            TextButton(
                              onPressed: _reload,
                              child: Text(tr('다시 시도')),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: DiaryStyle.motion(context),
                        child: _graph
                            ? ReadingGraph(
                                key: const ValueKey('diary-graph'),
                                month: _month,
                                days: _days,
                                monthly: _monthly,
                                onMonthlyChanged: (v) =>
                                    setState(() => _monthly = v),
                                onDay: _showDay,
                                onMonth: (m) => setState(() {
                                  _month = m;
                                  _monthly = false;
                                }),
                              )
                            : _DiaryCalendar(
                                key: ValueKey(
                                  'calendar-${_month.year}-${_month.month}',
                                ),
                                month: _month,
                                now: _now,
                                days: _days,
                                selectedDay: _selectedDay,
                                onDay: _showDay,
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiaryCalendar extends StatelessWidget {
  const _DiaryCalendar({
    super.key,
    required this.month,
    required this.now,
    required this.days,
    required this.selectedDay,
    required this.onDay,
  });
  final DateTime month, now;
  final List<DiaryDay> days;
  final String? selectedDay;
  final ValueChanged<DiaryDay> onDay;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final count = DateTime(month.year, month.month + 1, 0).day;
      final offset = month.weekday % 7;
      final weeks = ((offset + count) / 7).ceil();
      final width = c.maxWidth / 7;
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final emptyHeight = days.isEmpty ? 52.0 : 0.0;
      final height = math.max(
        84.0 + 20 * (scale.clamp(1, 1.8) - 1),
        (c.maxHeight - 40 - emptyHeight) / weeks,
      );
      final index = {for (final d in days) d.date: d};
      return SingleChildScrollView(
        child: Column(
          children: [
            if (days.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                child: Text(
                  tr('책을 읽으면 쿠피가 여기에 남아요'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DiaryStyle.muted,
                    height: 1.5,
                  ),
                ),
              ),
            Row(
              children: List.generate(
                7,
                (i) => Expanded(
                  child: SizedBox(
                    height: 36,
                    child: Center(
                      child: Text(
                        DateFormat.E(
                          AppLanguage.instance.code,
                        ).format(DateTime(2026, 11, 1 + i)),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: i == 0
                              ? DiaryStyle.sunday
                              : i == 6
                              ? DiaryStyle.saturday
                              : DiaryStyle.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: height * weeks,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: height,
                ),
                itemCount: weeks * 7,
                itemBuilder: (context, i) {
                  final number = i - offset + 1;
                  if (number < 1 || number > count) {
                    return const SizedBox.shrink();
                  }
                  final date = DateTime(month.year, month.month, number);
                  final record = index[diaryDate(date)];
                  final active =
                      record != null && record.duration.inMilliseconds > 0;
                  final today = diaryDate(date) == diaryDate(now);
                  final selected = selectedDay == diaryDate(date);
                  final dayColor = date.weekday == 7
                      ? DiaryStyle.sunday
                      : date.weekday == 6
                      ? DiaryStyle.saturday
                      : DiaryStyle.ink;
                  final time = active ? diaryTime(record.duration) : '';
                  return Semantics(
                    label:
                        '${DateFormat.yMd(AppLanguage.instance.code).format(date)}${active ? ', $time' : ''}',
                    button: active,
                    selected: selected,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: ValueKey('diary-day-$number'),
                        onTap: active ? () => onDay(record) : null,
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: DiaryStyle.motion(context),
                          margin: const EdgeInsets.fromLTRB(2, 3, 2, 5),
                          padding: const EdgeInsets.fromLTRB(3, 5, 3, 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? DiaryStyle.green.withValues(alpha: .4)
                                  : Colors.transparent,
                            ),
                            color: selected
                                ? DiaryStyle.green.withValues(alpha: .035)
                                : null,
                          ),
                          child: Column(
                            children: [
                              Align(
                                alignment: Alignment.topRight,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: today ? DiaryStyle.green : null,
                                  ),
                                  child: Text(
                                    '$number',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: today
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: today ? Colors.white : dayColor,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: active
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: SizedBox(
                                                width: math.min(
                                                  88,
                                                  width * .95,
                                                ),
                                                height: math.min(
                                                  66,
                                                  math.max(
                                                    24,
                                                    height - 70 * scale,
                                                  ),
                                                ),
                                                child: const KoofyDiaryStamp(),
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              width < 70 &&
                                                      record.duration.inHours >
                                                          0
                                                  ? time.replaceFirst(' ', '\n')
                                                  : time,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                height: 1.3,
                                                fontWeight: FontWeight.w500,
                                                color: DiaryStyle.ink,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class DiaryDayPage extends StatelessWidget {
  const DiaryDayPage({super.key, required this.day});
  final DiaryDay day;
  void _members(BuildContext context, DiaryEntry entry) =>
      showReaderDialog<void>(
        context: context,
        builder: (context) => ReaderAlertDialog(
          title: Text(entry.book.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final member in entry.members.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(member.key),
                  subtitle: Text(
                    diaryTime(Duration(milliseconds: member.value)),
                  ),
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(day.date);
    final entries = [...day.entries]
      ..sort((a, b) => b.milliseconds.compareTo(a.milliseconds));
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.yMMMd(AppLanguage.instance.code).format(date)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DiaryStyle.maxWidth),
            child: LayoutBuilder(
              builder: (context, c) {
                final columns = catalogShelfColumns(
                  window: MediaQuery.sizeOf(context),
                  shelfWidth: c.maxWidth - 40,
                  textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
                );
                final coverWidth =
                    (c.maxWidth - 40 - (columns - 1) * 18) / columns;
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('독서 시간'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: DiaryStyle.muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              diaryTime(day.duration),
                              style: const TextStyle(
                                fontSize: 30,
                                height: 1.2,
                                letterSpacing: -.8,
                                fontWeight: FontWeight.w600,
                                color: DiaryStyle.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 28,
                          mainAxisExtent: coverWidth * 1.4 + 108 * scale,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: DiaryCover(book: e.book)),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 36 * scale,
                                child: Text(
                                  e.book.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                    color: DiaryStyle.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Tooltip(
                                message: diaryExactTime(e.duration),
                                child: Text(
                                  diaryTime(e.duration),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: DiaryStyle.green,
                                  ),
                                ),
                              ),
                              if (e.members.isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () => _members(context, e),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      foregroundColor: DiaryStyle.muted,
                                    ),
                                    child: Text(
                                      tr('회차별 기록'),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DiaryCover extends StatelessWidget {
  const DiaryCover({super.key, required this.book});
  final DiaryBook book;
  @override
  Widget build(BuildContext context) => book.cover != null
      ? ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(
            base64Decode(book.cover!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        )
      : _fallback();
  Widget _fallback() => BookCover(
    compact: true,
    book: Book.asset(
      id: book.id,
      title: book.title,
      author: '',
      description: '',
      assetPath: '',
    ),
  );
}

/// Crop the existing sticker's lettering at layout time; use the same Koofy in all languages.
class KoofyDiaryStamp extends StatelessWidget {
  const KoofyDiaryStamp({super.key});
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.contain,
    child: SizedBox(
      width: 512,
      height: 350,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.bottomCenter,
          maxHeight: 512,
          maxWidth: 512,
          child: Image.asset(
            'assets/images/diary/koofy_stamp.png',
            width: 512,
            height: 512,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
