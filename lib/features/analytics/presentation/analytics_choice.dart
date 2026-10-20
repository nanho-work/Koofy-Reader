import 'package:flutter/material.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import '../data/reader_analytics.dart';

const analyticsExplanation =
    '앱 실행, 독서 시간, 책 가져오기, 소설·글꼴 다운로드와 기능 사용 정보를 Google Analytics로 분석합니다. 앱 인스턴스 식별자와 기기·앱 정보가 함께 처리됩니다. 개인 책 제목·본문·파일명·검색어는 보내지 않습니다. 거절해도 모든 독서 기능을 이용할 수 있으며 설정에서 변경할 수 있습니다.';

class AnalyticsChoice extends StatefulWidget {
  const AnalyticsChoice({super.key, required this.child, this.service});
  final Widget child;
  final ReaderAnalytics? service;
  @override
  State<AnalyticsChoice> createState() => _AnalyticsChoiceState();
}

class _AnalyticsChoiceState extends State<AnalyticsChoice> {
  ReaderAnalytics get analytics => widget.service ?? ReaderAnalytics.instance;
  bool busy = false;
  String? error;
  Future<void> choose(bool value) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await analytics.choose(value);
    } catch (_) {
      if (mounted) setState(() => error = tr('설정을 저장하지 못했습니다. 다시 시도해 주세요.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: analytics,
    builder: (context, _) {
      final service = analytics;
      if (!service.loaded || service.choice != null) return widget.child;
      return Scaffold(
        appBar: AppBar(title: Text(tr('사용 통계 (선택)'))),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(tr(analyticsExplanation)),
              const SizedBox(height: 24),
              if (error != null) Text(error!),
              FilledButton(
                onPressed: busy ? null : () => choose(true),
                child: Text(tr('사용 통계 허용')),
              ),
              TextButton(
                onPressed: busy ? null : () => choose(false),
                child: Text(tr('허용하지 않고 계속')),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class AnalyticsSetting extends StatelessWidget {
  const AnalyticsSetting({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ReaderAnalytics.instance,
    builder: (context, _) => SwitchListTile(
      title: Text(tr('사용 통계 (선택)')),
      subtitle: Text(tr(analyticsExplanation)),
      value: ReaderAnalytics.instance.choice == true,
      onChanged: (value) async {
        try {
          await ReaderAnalytics.instance.choose(value);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr('설정을 저장하지 못했습니다. 다시 시도해 주세요.'))),
            );
          }
        }
      },
    ),
  );
}
