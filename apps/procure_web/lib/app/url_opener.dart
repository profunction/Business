import 'url_opener_stub.dart' if (dart.library.js_interop) 'url_opener_web.dart' as impl;

/// 在新分页打开网址（HitPay 付款页）。网页版以外（测试）回传 false，画面改成显示网址让人复制
abstract class UrlOpener {
  Future<bool> open(String url);
}

UrlOpener platformUrlOpener() => impl.createUrlOpener();
