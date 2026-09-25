import 'package:flutter/material.dart';

/// Storage must be ready before the library can write. Startup failures remain
/// visible and retryable instead of leaving the native splash on screen.
class ReaderBootstrap extends StatefulWidget {
  const ReaderBootstrap({
    super.key,
    required this.initialize,
    required this.child,
  });
  final Future<void> Function() initialize;
  final Widget child;
  @override
  State<ReaderBootstrap> createState() => _ReaderBootstrapState();
}

class _ReaderBootstrapState extends State<ReaderBootstrap> {
  late Future<void> _startup;
  @override
  void initState() {
    super.initState();
    _startup = Future.sync(widget.initialize);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _startup,
    builder: (context, state) {
      if (state.connectionState == ConnectionState.done && !state.hasError) {
        return widget.child;
      }
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: state.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '앱을 준비하지 못했습니다. 기존 책과 기록은 삭제하지 않았습니다. 저장 공간을 확인한 뒤 다시 시도해 주세요.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => setState(() {
                              _startup = Future.sync(widget.initialize);
                            }),
                            child: const Text('다시 시도'),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(
                        semanticsLabel: '기록을 안전하게 준비하는 중',
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
