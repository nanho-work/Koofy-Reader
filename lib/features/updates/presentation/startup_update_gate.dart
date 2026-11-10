import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/update_service.dart';
import 'update_store_action.dart';

/// Checks the minimum version before any library or reader route is shown.
/// Waiting is bounded; a late result can never interrupt a reading session.
class StartupUpdateGate extends ConsumerWidget {
  const StartupUpdateGate({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(updateNoticeProvider);
    if (check.isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(tr("업데이트 확인 중…")),
            ],
          ),
        ),
      );
    }
    final notice = check.valueOrNull;
    if (notice == null || !notice.required) return child;
    return PopScope(
      canPop: false,
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
                      tr("업데이트가 필요합니다"),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(notice.message),
                    const SizedBox(height: 12),
                    Text(
                      tr("새 버전 {0}", [notice.latestVersion]),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    UpdateStoreAction(url: notice.storeUrl),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
