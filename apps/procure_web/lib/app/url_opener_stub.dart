import 'url_opener.dart';

class _NoUrlOpener implements UrlOpener {
  @override
  Future<bool> open(String url) async => false;
}

UrlOpener createUrlOpener() => _NoUrlOpener();
