import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/privacy_service.dart';

const readerSupportEmail = 'koofylab@gmail.com';
const readerPolicyUrl = 'https://www.koofy.co.kr/koofy-reader/privacy';
const readerSupportUrl = 'https://www.koofy.co.kr/koofy-reader/support';

Future<void> openReaderLink(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('연결할 앱을 열지 못했습니다. 표시된 주소를 복사해 이용해 주세요.')),
  );
}

class PrivacyGate extends ConsumerStatefulWidget {
  const PrivacyGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends ConsumerState<PrivacyGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(privacyServiceProvider).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(privacyStateProvider).valueOrNull;
    if (state == null || !state.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.choice == null) {
      return Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const AdvertisingChoicesPage(firstRun: true),
        ),
      );
    }
    return widget.child;
  }
}

class AdvertisingChoicesPage extends ConsumerStatefulWidget {
  const AdvertisingChoicesPage({super.key, this.firstRun = false});
  final bool firstRun;
  @override
  ConsumerState<AdvertisingChoicesPage> createState() =>
      _AdvertisingChoicesPageState();
}

class _AdvertisingChoicesPageState
    extends ConsumerState<AdvertisingChoicesPage> {
  AdvertisingChoice? _selection;
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final current = ref.watch(privacyStateProvider).valueOrNull;
    final service = ref.read(privacyServiceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? '쿠피리더 시작하기' : '광고 선택 변경')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('개인정보와 광고', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text(
              '책과 읽던 위치는 기기에 보관합니다. 서재·독서 화면의 배너와 선택형 리워드 광고는 Unity LevelPlay의 Unity Ads·ironSource Ads가 제공합니다.',
            ),
            const SizedBox(height: 12),
            const Text(
              '광고 제공·측정·부정 이용 방지를 위해 IP 주소, 기기·앱 정보와 광고 이용 정보가 처리될 수 있습니다. 맞춤형 광고를 허용하면 허용된 식별자와 다른 앱·웹 이용 관련 정보가 개인화에 사용될 수 있습니다.',
            ),
            const SizedBox(height: 12),
            const Text(
              '어느 항목을 선택해도 독서는 이용할 수 있습니다. 비맞춤형 광고도 제공·보안에 필요한 정보는 처리합니다. 선택은 설정에서 변경할 수 있습니다.',
            ),
            if (service.isIOS)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'iOS 추적 허가는 Apple의 별도 권한입니다. 맞춤형 광고를 선택한 경우 아직 결정하지 않은 추적 허가를 요청합니다. 거부해도 비맞춤형 광고와 독서를 이용할 수 있습니다.',
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReaderPrivacyPolicyPage(),
                ),
              ),
              child: const Text('개인정보처리방침 읽기'),
            ),
            RadioGroup<AdvertisingChoice>(
              groupValue: _selection,
              onChanged: (v) => setState(() => _selection = v),
              child: Column(
                children: [
                  RadioListTile<AdvertisingChoice>(
                    title: const Text('비맞춤형 광고 이용'),
                    subtitle: const Text('맞춤형 광고와 이를 위한 정보 공유에 동의하지 않습니다.'),
                    value: AdvertisingChoice.standard,
                    enabled: !_busy,
                  ),
                  RadioListTile<AdvertisingChoice>(
                    title: const Text('맞춤형 광고 허용 (선택)'),
                    subtitle: const Text('안내된 광고 개인화와 관련 정보 처리·공유에 동의합니다.'),
                    value: AdvertisingChoice.personalized,
                    enabled: !_busy,
                  ),
                ],
              ),
            ),
            if (current?.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(current!.error!),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _selection == null
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await service.choose(_selection!);
                        if (context.mounted && !widget.firstRun) {
                          Navigator.of(context).pop();
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('선택을 저장하지 못했습니다. 다시 시도해 주세요.'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Text(
                _busy
                    ? '적용 중…'
                    : widget.firstRun
                    ? '선택하고 시작하기'
                    : '선택 저장',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacySettingsPage extends ConsumerWidget {
  const PrivacySettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(privacyStateProvider).valueOrNull;
    final service = ref.read(privacyServiceProvider);
    final choice = state?.choice;
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보 및 광고')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('광고 선택'),
            subtitle: Text(
              choice == null
                  ? '선택 전'
                  : choice == AdvertisingChoice.standard
                  ? '비맞춤형 광고'
                  : '맞춤형 광고 허용',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdvertisingChoicesPage(),
              ),
            ),
          ),
          if (state?.changedAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '최근 선택: ${state!.changedAt!.toLocal().toString().split('.').first}\n안내 버전: ${PrivacyService.policyVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (state?.error != null)
            ListTile(
              title: Text(state!.error!),
              trailing: IconButton(
                tooltip: '다시 적용',
                onPressed: () => service.refresh(),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (service.isIOS) ...[
            ListTile(
              title: const Text('iOS 추적 허가'),
              subtitle: Text(switch (state?.att) {
                'authorized' => '허용됨',
                'denied' => '허용 안 함',
                'restricted' => '기기에서 제한됨',
                _ => '아직 결정하지 않음',
              }),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openReaderLink(context, Uri.parse('app-settings:')),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '추적 허가를 거부하면 비맞춤형 광고가 적용됩니다. 기기 설정에서 권한을 변경한 후 돌아오면 다시 확인합니다.',
              ),
            ),
          ],
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('개인정보처리방침'),
            subtitle: const Text('인터넷 없이도 확인할 수 있습니다.'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ReaderPrivacyPolicyPage(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('문의하기'),
            subtitle: const Text(readerSupportEmail),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ReaderSupportPage(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('부적절한 광고 신고'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ReaderSupportPage(reportAd: true),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('오픈소스 라이선스'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Koofy Reader',
            ),
          ),
        ],
      ),
    );
  }
}

class ReaderPrivacyPolicyPage extends StatefulWidget {
  const ReaderPrivacyPolicyPage({super.key});
  @override
  State<ReaderPrivacyPolicyPage> createState() =>
      _ReaderPrivacyPolicyPageState();
}

class _ReaderPrivacyPolicyPageState extends State<ReaderPrivacyPolicyPage> {
  late final _document = rootBundle
      .loadString('assets/legal/reader_privacy.json')
      .then((v) => jsonDecode(v) as Map<String, dynamic>);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('개인정보처리방침')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _document,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: SelectableText(
              '방침을 불러오지 못했습니다.\n$readerPolicyUrl\n$readerSupportEmail',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final document = data['translations']['ko'];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              document['title'],
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('최종 업데이트: ${data['updatedAt']}'),
            const SizedBox(height: 16),
            Text(document['intro']),
            for (final section in document['sections']) ...[
              const SizedBox(height: 24),
              Text(
                section['heading'],
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final p in section['paragraphs'])
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(p),
                ),
              for (final link in section['links'] ?? [])
                TextButton(
                  onPressed: () =>
                      openReaderLink(context, Uri.parse(link['href'])),
                  child: Text(link['label']),
                ),
            ],
            const SizedBox(height: 24),
            const SelectableText(readerPolicyUrl),
            TextButton(
              onPressed: () =>
                  openReaderLink(context, Uri.parse(readerPolicyUrl)),
              child: const Text('웹에서 최신 방침 보기'),
            ),
          ],
        );
      },
    ),
  );
}

class ReaderSupportPage extends StatelessWidget {
  const ReaderSupportPage({super.key, this.reportAd = false});
  final bool reportAd;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(reportAd ? '부적절한 광고 신고' : '문의하기')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          reportAd
              ? '광고가 나온 시각, 서재·독서 화면 등 표시 위치, 광고 내용을 알려 주세요. 필요하면 개인정보와 책 본문을 가린 화면 캡처를 직접 첨부해 주세요.'
              : '기기 종류, OS 버전, 발생한 문제와 재현 방법을 알려 주세요. 개인정보 관련 요청도 같은 메일로 접수합니다.',
        ),
        const SizedBox(height: 16),
        const Text('Koofy Lab 대표 메일'),
        const SelectableText(readerSupportEmail),
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('메일 주소 복사'),
          onPressed: () async {
            await Clipboard.setData(
              const ClipboardData(text: readerSupportEmail),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('메일 주소를 복사했습니다.')));
            }
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.mail_outline),
          label: const Text('메일 작성하기'),
          onPressed: () => openReaderLink(
            context,
            Uri(
              scheme: 'mailto',
              path: readerSupportEmail,
              query:
                  'subject=${Uri.encodeComponent(reportAd ? '[쿠피리더] 광고 신고' : '[쿠피리더] 문의')}&body=${Uri.encodeComponent(reportAd ? '발생 시각:\n광고 위치:\n광고 내용:\n기기 및 OS:\n' : '기기 및 OS:\n문의 내용:\n')}',
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '메일 앱이 없으면 주소를 복사해 사용 중인 메일 서비스에서 보내 주세요. 본문·독서 기록은 자동 첨부하지 않습니다.',
        ),
        const SizedBox(height: 20),
        const SelectableText(readerSupportUrl),
        TextButton(
          onPressed: () => openReaderLink(context, Uri.parse(readerSupportUrl)),
          child: const Text('웹 지원 페이지 열기'),
        ),
      ],
    ),
  );
}
