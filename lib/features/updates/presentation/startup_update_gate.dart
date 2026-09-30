import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/update_service.dart';
import '../domain/update_policy.dart';

final updateLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

/// Mounted after privacy onboarding, before any library/reader route is shown.
/// Waiting is bounded; a late result can never interrupt a reading session.
class StartupUpdateGate extends ConsumerStatefulWidget {
  const StartupUpdateGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends ConsumerState<StartupUpdateGate> {
  late final Future<UpdateNotice?> _check;
  bool _opening = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _check = ref.read(updateServiceProvider).checkOnColdStart();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UpdateNotice?>(
    future: _check,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('업데이트 확인 중…'),
              ],
            ),
          ),
        );
      }
      final notice = snapshot.data;
      if (notice == null || ref.read(updateServiceProvider).dismissed) {
        return widget.child;
      }
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !notice.required) _later();
        },
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.system_update_outlined,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        notice.required ? '업데이트가 필요합니다' : notice.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(notice.message),
                      const SizedBox(height: 12),
                      Text(
                        '새 버전 ${notice.latestVersion}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, semanticsLabel: _error),
                        SelectableText(notice.storeUrl.toString()),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _opening ? null : () => _open(notice),
                        child: Text(_opening ? '스토어 여는 중…' : '업데이트'),
                      ),
                      if (!notice.required)
                        TextButton(
                          onPressed: _opening ? null : _later,
                          child: const Text('나중에'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  void _later() {
    ref.read(updateServiceProvider).dismissForSession();
    setState(() {});
  }

  Future<void> _open(UpdateNotice notice) async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final opened = await ref.read(updateLinkLauncherProvider)(
        notice.storeUrl,
      );
      if (!opened && mounted) {
        setState(() => _error = '스토어를 열지 못했습니다. 다시 누르거나 아래 주소를 복사해 이용해 주세요.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '스토어를 열지 못했습니다. 다시 누르거나 아래 주소를 복사해 이용해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
