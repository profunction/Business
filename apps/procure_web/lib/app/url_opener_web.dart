import 'package:web/web.dart' as web;

import 'url_opener.dart';

class _WebUrlOpener implements UrlOpener {
  @override
  Future<bool> open(String url) async {
    if (!url.startsWith('https://')) return false;
    web.window.open(url, '_blank', 'noopener');
    return true;
  }
}

UrlOpener createUrlOpener() => _WebUrlOpener();
