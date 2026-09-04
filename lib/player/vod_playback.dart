import '../config/api_config.dart';

/// CMS 片源播放：统一请求头
class VodPlayback {
  VodPlayback._();

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static Map<String, String> get httpHeaders => {
        'User-Agent': userAgent,
        'Referer': '${ApiConfig.macCmsBase}/',
      };

  static const playbackRates = <double>[0.75, 1.0, 1.25, 1.5, 2.0];
  static String rateLabel(double rate) {
    if (rate == rate.roundToDouble()) {
      return '${rate.toInt().toString()}x';
    }
    return '${rate}x';
  }
}
