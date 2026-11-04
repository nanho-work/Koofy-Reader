import 'package:koofy_reader/core/localization/app_language.dart';

String diaryTime(Duration duration) {
  if (duration.inMinutes == 0 && duration.inMilliseconds > 0) {
    return tr('1분 미만');
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return tr('{0}분', [minutes]);
  return minutes == 0
      ? tr('{0}시간', [hours])
      : tr('{0}시간 {1}분', [hours, minutes]);
}

String diaryExactTime(Duration d) =>
    '${d.inHours > 0 ? '${d.inHours}:' : ''}${d.inHours > 0 ? d.inMinutes.remainder(60).toString().padLeft(2, '0') : d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
