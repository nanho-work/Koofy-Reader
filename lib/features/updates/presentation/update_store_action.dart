import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:url_launcher/url_launcher.dart';

final updateLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

class UpdateStoreAction extends ConsumerStatefulWidget {
  const UpdateStoreAction({super.key, required this.url});

  final Uri url;

  @override
  ConsumerState<UpdateStoreAction> createState() => _UpdateStoreActionState();
}

class _UpdateStoreActionState extends ConsumerState<UpdateStoreAction> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _failed = false;
    });
    var opened = false;
    try {
      opened = await ref.read(updateLinkLauncherProvider)(widget.url);
    } catch (_) {
      // A missing store app or a platform error both allow a retry.
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _failed = !opened;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_failed) ...[
        Text(tr("스토어를 열지 못했습니다. 다시 누르거나 아래 주소를 복사해 이용해 주세요.")),
        SelectableText(widget.url.toString()),
        const SizedBox(height: 16),
      ],
      FilledButton(
        onPressed: _opening ? null : _open,
        child: Text(_opening ? tr("스토어 여는 중…") : tr("업데이트")),
      ),
    ],
  );
}
