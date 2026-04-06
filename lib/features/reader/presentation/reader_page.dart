import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_view.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late final ScrollController _scrollController;
  late final Future<String> _contentFuture;
  Timer? _saveDebounce;
  bool _restoreRequested = false;
  double _progressRatio = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _contentFuture = ref
        .read(bookRepositoryProvider)
        .readBookContent(widget.book);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveProgress();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    final ratio = maxExtent <= 0
        ? 0.0
        : (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
    if ((ratio - _progressRatio).abs() > 0.001 && mounted) {
      setState(() {
        _progressRatio = ratio;
      });
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), _saveProgress);
  }

  Future<void> _saveProgress() async {
    final repository = ref.read(readerRepositoryProvider);
    await repository.saveProgress(
      ReadingProgress(
        bookId: widget.book.id,
        positionRatio: _progressRatio,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _restoreProgress([int retry = 0]) async {
    if (!_scrollController.hasClients || !mounted) {
      return;
    }
    final saved = await ref
        .read(readerRepositoryProvider)
        .loadProgress(widget.book.id);
    if (saved == null) {
      return;
    }

    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent == 0 && retry < 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreProgress(retry + 1);
      });
      return;
    }

    final targetOffset = (maxExtent * saved.positionRatio).clamp(
      0.0,
      maxExtent,
    );
    _scrollController.jumpTo(targetOffset);
    if (mounted) {
      setState(() {
        _progressRatio = saved.positionRatio.clamp(0.0, 1.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            icon: const Icon(Icons.settings),
            tooltip: '설정',
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '책 본문을 열 수 없습니다.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }
          final content = snapshot.data ?? '';
          if (!_restoreRequested) {
            _restoreRequested = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _restoreProgress();
            });
          }
          return ReaderView(
            scrollController: _scrollController,
            content: content,
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(value: _progressRatio),
                  ),
                  const SizedBox(width: 10),
                  Text('${(_progressRatio * 100).round()}%'),
                ],
              ),
            ),
            const AdFooterWidget(),
          ],
        ),
      ),
    );
  }
}
