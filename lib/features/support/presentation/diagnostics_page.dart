import 'package:koofy_reader/core/localization/app_language.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'package:koofy_reader/features/updates/data/update_service.dart';

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});
  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  Future<String>? report;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    report ??= buildReport(
      MediaQuery.sizeOf(context),
      MediaQuery.textScalerOf(context).scale(16) / 16,
    );
  }

  Future<String> buildReport(Size size, double scale) async {
    final lines = <String>[
      tr("쿠피리더 진단 정보"),
      tr("운영체제: {0}", [Platform.operatingSystem]),
      tr("OS 버전: {0}", [Platform.operatingSystemVersion]),
      tr("화면: {0} × {1} (논리 픽셀)", [size.width.round(), size.height.round()]),
      tr("시스템 글자 배율: {0}", [scale.toStringAsFixed(2)]),
    ];
    try {
      final info = await ref.read(installedPackageProvider.future);
      lines.add(tr("앱: {0} ({1})", [info.version, info.buildNumber]));
    } catch (_) {
      lines.add(tr("앱 버전: 확인 실패"));
    }
    try {
      final native = await ref.read(nativeReaderServicesProvider.future);
      final data = await native.coordinator.store.exportBackup(<String>{});
      final preferences = jsonDecode(data['preferences'] as String) as Map;
      // Whitelist only layout values; no file paths, book IDs, quotes or locators.
      for (final key in [
        'fontScale',
        'columnCount',
        'scroll',
        'theme',
        'pageTurnStyle',
        'lineHeight',
        'paragraphSpacing',
        'pageMargins',
      ]) {
        if (preferences.containsKey(key)) {
          lines.add('$key: ${preferences[key]}');
        }
      }
    } catch (_) {
      lines.add(tr("독서 설정: 확인 실패"));
    }
    lines.add(tr("\n발생한 문제와 재현 순서를 함께 적어 문의해 주세요."));
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr("문제 신고용 진단 정보"))),
    body: FutureBuilder<String>(
      future: report,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              tr(
                "아래 정보를 확인한 뒤 복사해 문의에 첨부할 수 있습니다. 책 본문·파일명·독서 위치·광고 식별자는 포함하지 않으며 자동 전송하지 않습니다.",
              ),
            ),
            const SizedBox(height: 20),
            SelectableText(snapshot.data!),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: snapshot.data!));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(tr("진단 정보를 복사했습니다."))));
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: Text(tr("진단 정보 복사")),
            ),
          ],
        );
      },
    ),
  );
}
