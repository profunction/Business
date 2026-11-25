// WholesaleApi 批发商端不连服务器也能测的部分：错误代码、等 AI 读完、上传前的检查；
// 送出去的请求（顺序、过滤条件）用 http 的 MockClient 看
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

class FakeApi extends WholesaleApi {
  FakeApi({this.timeout = const Duration(milliseconds: 200)}) : super(SupabaseClient('http://127.0.0.1:1', 'test-key'));

  final Duration timeout;

  final calls = <String>[];
  final statuses = <Object>[]; // ImportStatus 或 AppError，一次 getImport 用一个
  Object? startParseError;

  /// getImport 回传的导入：什么时候建的、AI 什么时候开始读（ai_raw.claimed_at；null = 还没人读）
  DateTime importCreatedAt = DateTime(2026);
  DateTime? claimedAt;
  int polls = 0;

  @override
  Duration get importPollInterval => const Duration(milliseconds: 1);

  @override
  Duration get importPollTimeout => timeout;

  @override
  Future<PriceListImport> getImport(String importId) async {
    polls++;
    final next = statuses.isEmpty ? ImportStatus.processing : statuses.removeAt(0);
    if (next is AppError) throw next;
    final claimed = claimedAt;
    return PriceListImport(
      id: importId,
      wholesalerId: 'w',
      filePath: 'w/x.jpg',
      fileType: ImportFileType.image,
      status: next as ImportStatus,
      aiRaw: claimed == null ? null : {'state': 'running', 'claimed_at': claimed.toUtc().toIso8601String()},
      createdAt: importCreatedAt,
    );
  }

  @override
  Future<String> uploadPriceList(String wholesalerId, Uint8List bytes, String ext, String contentType) async {
    calls.add('upload $ext $contentType');
    return '$wholesalerId/abc.$ext';
  }

  @override
  Future<PriceListImport> createImport({
    required String wholesalerId,
    required String filePath,
    required ImportFileType fileType,
  }) async {
    calls.add('create $filePath ${fileType.name}');
    return PriceListImport(
      id: 'imp-1',
      wholesalerId: wholesalerId,
      filePath: filePath,
      fileType: fileType,
      status: ImportStatus.processing,
      createdAt: DateTime(2026),
    );
  }

  @override
  Future<void> startParse(String importId) async {
    calls.add('parse $importId');
    final e = startParseError;
    if (e != null) throw e;
  }

  /// markImportFailed 标不到（例如 AI 其实已经开始读了：ai_raw 不是空的）
  bool markMisses = false;

  /// discardImport 丢这个错误（例如没网络）
  Object? discardError;

  @override
  Future<bool> markImportFailed(String importId, String code) async {
    calls.add('failed $importId $code');
    return !markMisses;
  }

  @override
  Future<bool> discardImport(PriceListImport import) async {
    calls.add('discard ${import.id} ${import.filePath}');
    final e = discardError;
    if (e != null) throw e;
    return true;
  }
}

/// 假的服务器：记下每个请求（method path?query），回传 [reply] 给的内容
class Recorder {
  final requests = <String>[];

  /// 第几个请求（从 0 开始）丢 ClientException（没网络）
  int? failAt;

  late final api = WholesaleApi(
    SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((req) async {
        final n = requests.length;
        requests.add('${req.method} ${req.url.path}?${Uri.decodeQueryComponent(req.url.query)}');
        if (n == failAt) throw http.ClientException('Connection reset by peer', req.url);
        final body = req.url.path.contains('/storage/')
            ? '[]'
            : req.method == 'GET'
            ? jsonEncode({
                'id': 'w1',
                'name': 'A',
                'phone': '60120000002',
                'whatsapp_phone': null,
                'notify_channel': 'whatsapp',
                'whatsapp_opt_in_at': '2026-11-25T00:00:00Z',
              })
            : '[{"id":"x"}]';
        return http.Response(body, 200, headers: {'content-type': 'application/json'}, request: req);
      }),
    ),
  );
}

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 1)]);

void main() {
  group('AppError.fromStorage', () {
    test('太大 / 格式不收 / 没权限', () {
      expect(
        AppError.fromStorage(const StorageException('Payload too large', statusCode: '413')).code,
        'FILE_TOO_LARGE',
      );
      expect(
        AppError.fromStorage(const StorageException('mime type image/heic is not supported', statusCode: '415')).code,
        'UNSUPPORTED_FILE',
      );
      expect(
        AppError.fromStorage(const StorageException('new row violates row-level security policy', statusCode: '403'))
            .code,
        'NOT_ALLOWED',
      );
      expect(
        AppError.fromStorage(const StorageException('The object exceeded the maximum allowed size', statusCode: '400'))
            .code,
        'FILE_TOO_LARGE',
      );
      expect(AppError.fromStorage(const StorageException('boom', statusCode: '500')).code, 'UNKNOWN');
    });
  });

  group('AppError.fromFunction', () {
    test('函数回传的代码优先', () {
      final e = AppError.fromFunction(
        const FunctionsHttpException(status: 409, details: {'error': 'IMPORT_NOT_PROCESSING'}),
      );
      expect(e.code, 'IMPORT_NOT_PROCESSING');
      expect(e.detail, '409');
      expect(
        AppError.fromFunction(const FunctionsHttpException(status: 400, details: '{"error":"BAD_REQUEST"}')).code,
        'BAD_REQUEST',
      );
    });

    test('没有代码就按 HTTP 状态', () {
      expect(AppError.fromFunction(const FunctionsHttpException(status: 401)).code, 'AUTH');
      expect(AppError.fromFunction(const FunctionsHttpException(status: 404, details: 'Not Found')).code, 'NOT_FOUND');
      expect(
        AppError.fromFunction(
          const FunctionsHttpException(status: 404),
          byStatus: const {404: 'IMPORT_NOT_FOUND'},
        ).code,
        'IMPORT_NOT_FOUND',
      );
      expect(
        AppError.fromFunction(const FunctionsHttpException(status: 500, details: {'error': 'oops'})).code,
        'UNKNOWN',
      );
    });

    test('没网络 / 登录过期 / 平台转发失败', () {
      expect(AppError.fromFunction(const FunctionsFetchException(details: 'SocketException')).code, 'NETWORK');
      final expired = AppError.fromFunction(const FunctionsFetchException(details: AuthException('expired')));
      expect((expired.code, expired.detail), ('AUTH', AppError.sessionExpired));
      expect(AppError.fromFunction(const FunctionsRelayException(status: 502)).code, 'UNKNOWN');
    });

    test('parse-price-list 不肯读：429 用量满了（detail 是要等几秒）、403 停权、503 暂时叫不到', () {
      final quota = AppError.fromFunction(
        const FunctionsHttpException(
          status: 429,
          details: {'error': 'TOO_MANY_IMPORTS', 'retry_after': 420, 'window': 'burst'},
        ),
      );
      expect(quota.code, 'TOO_MANY_IMPORTS');
      expect(quota.retryAfter, const Duration(minutes: 7));
      expect(
        AppError.fromFunction(const FunctionsHttpException(status: 429, details: '{"error":"TOO_MANY_IMPORTS"}'))
            .retryAfter,
        isNull,
        reason: '没给 retry_after：不知道要等多久',
      );
      expect(
        AppError.fromFunction(const FunctionsHttpException(status: 403, details: {'error': 'WHOLESALER_SUSPENDED'}))
            .code,
        'WHOLESALER_SUSPENDED',
      );
      expect(
        AppError.fromFunction(const FunctionsHttpException(status: 503, details: {'error': 'QUOTA_UNAVAILABLE'})).code,
        'QUOTA_UNAVAILABLE',
      );
      expect(const AppError('IMPORT_ROW_INCOMPLETE', detail: '420').retryAfter, isNull);
    });

    test('parse-price-list 自己验 JWT：401 {"error":"UNAUTHORIZED"} = 登录过期（AUTH），不是不认识的错误', () {
      final e = AppError.fromFunction(const FunctionsHttpException(status: 401, details: {'error': 'UNAUTHORIZED'}));
      expect(e.code, 'AUTH');
      expect(e.detail, AppError.sessionExpired);
      expect(AppError.fromFunction(const FunctionsHttpException(status: 401)).detail, AppError.sessionExpired);
      expect(
        AppError.fromFunction(const FunctionsHttpException(status: 409, details: {'error': 'IMPORT_ALREADY_RUNNING'}))
            .code,
        'IMPORT_ALREADY_RUNNING',
      );
    });
  });

  group('watchImport', () {
    test('每次查都回传，读完（review）就停', () async {
      final api = FakeApi()..statuses.addAll([ImportStatus.processing, ImportStatus.processing, ImportStatus.review]);
      final seen = await api.watchImport('imp').map((i) => i.status).toList();
      expect(seen, [ImportStatus.processing, ImportStatus.processing, ImportStatus.review]);
    });

    test('中间没网络不算失败', () async {
      final api = FakeApi()..statuses.addAll([const AppError('NETWORK'), ImportStatus.failed]);
      expect(await api.watchImport('imp').map((i) => i.status).toList(), [ImportStatus.failed]);
    });

    test('服务器暂时出错（网关 502 → UNKNOWN）也不算失败，下一次再查', () async {
      final api = FakeApi()
        ..statuses.addAll([ImportStatus.processing, const AppError('UNKNOWN'), const AppError('DB_ERROR')])
        ..statuses.add(ImportStatus.review);
      expect(await api.watchImport('imp').map((i) => i.status).toList(), [
        ImportStatus.processing,
        ImportStatus.review,
      ]);
    });

    test('找不到那一份、没权限、登录过期：直接丢出来', () async {
      for (final code in ['IMPORT_NOT_FOUND', 'NOT_ALLOWED', 'AUTH']) {
        final api = FakeApi()..statuses.add(AppError(code));
        await expectLater(
          api.watchImport('imp').toList(),
          throwsA(isA<AppError>().having((e) => e.code, 'code', code)),
          reason: code,
        );
      }
    });

    test('AI 在读（刚占位）：不会再叫 AI', () async {
      final api = FakeApi()
        ..claimedAt = DateTime.now()
        ..importCreatedAt = DateTime.now().subtract(const Duration(minutes: 2))
        ..statuses.addAll([ImportStatus.processing, ImportStatus.processing, ImportStatus.review]);
      await api.watchImport('imp').drain<void>();
      expect(api.calls, isEmpty);
    });

    test('卡住了（从来没人开始读：叫 AI 的时候断线）→ 再叫一次 AI（只叫一次），读好了照样结束', () async {
      final api = FakeApi()
        ..importCreatedAt = DateTime.now().subtract(const Duration(minutes: 3))
        ..statuses.addAll([ImportStatus.processing, ImportStatus.processing, ImportStatus.review]);
      final seen = await api.watchImport('imp').map((i) => i.status).toList();
      expect(seen.last, ImportStatus.review);
      expect(api.calls, ['parse imp']);
    });

    test('卡住了（「在跑」超过 10 分钟：worker 死掉了）→ 再叫一次 AI', () async {
      final api = FakeApi()
        ..importCreatedAt = DateTime.now().subtract(const Duration(minutes: 30))
        ..claimedAt = DateTime.now().subtract(const Duration(minutes: 11))
        ..statuses.addAll([ImportStatus.processing, ImportStatus.review]);
      await api.watchImport('imp').drain<void>();
      expect(api.calls, ['parse imp']);
    });

    test('再叫 AI：已经有人在读（409 IMPORT_ALREADY_RUNNING）、没网络 → 不算失败，继续等', () async {
      for (final code in ['IMPORT_ALREADY_RUNNING', 'NETWORK', 'INTERNAL_ERROR']) {
        final api = FakeApi()
          ..startParseError = AppError(code)
          ..statuses.addAll([ImportStatus.processing, ImportStatus.review]);
        expect(await api.watchImport('imp').map((i) => i.status).toList(), [
          ImportStatus.processing,
          ImportStatus.review,
        ], reason: code);
        expect(api.calls, ['parse imp'], reason: '$code：不标成失败');
      }
    });

    test('从来没开始读、又叫不动（登录过期 / 函数没设定好）→ 标成失败，马上交出 failed（首页才会让老板重新上传）', () async {
      for (final (code, reason) in [('AUTH', 'AUTH'), ('CONFIG_MISSING', 'START_FAILED')]) {
        final api = FakeApi()
          ..startParseError = AppError(code)
          ..statuses.addAll([ImportStatus.processing, ImportStatus.failed]);
        expect(await api.watchImport('imp').map((i) => i.status).toList(), [
          ImportStatus.processing,
          ImportStatus.failed,
        ]);
        expect(api.calls, ['parse imp', 'failed imp $reason']);
      }
      // 批发商停权了：再叫也一样，标成失败（不会一直再叫）
      final suspended = FakeApi()
        ..startParseError = const AppError('WHOLESALER_SUSPENDED')
        ..statuses.addAll([ImportStatus.processing, ImportStatus.failed]);
      await suspended.watchImport('imp').drain<void>();
      expect(suspended.calls, ['parse imp', 'failed imp START_FAILED']);
      // 用量满了：不是失败（导入没动），等有位置再叫
      final quota = FakeApi()
        ..startParseError = const AppError('TOO_MANY_IMPORTS', detail: '300')
        ..statuses.addAll([ImportStatus.processing, ImportStatus.processing, ImportStatus.review]);
      await quota.watchImport('imp').drain<void>();
      expect(quota.calls, ['parse imp']);
      // 有人读过（有占位）的不标：可能还在读
      final running = FakeApi()
        ..startParseError = const AppError('CONFIG_MISSING')
        ..claimedAt = DateTime.now().subtract(const Duration(minutes: 11))
        ..statuses.addAll([ImportStatus.processing, ImportStatus.review]);
      await running.watchImport('imp').drain<void>();
      expect(running.calls, ['parse imp']);
    });

    test('等到最后还没人开始读（手机时间不准，看起来还不到 30 秒）→ 最后再叫一次 AI，才说 IMPORT_TIMEOUT', () async {
      final api = FakeApi()..importCreatedAt = DateTime.now().add(const Duration(hours: 1));
      await expectLater(
        api.watchImport('imp').drain<void>(),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'IMPORT_TIMEOUT')),
      );
      expect(api.calls, ['parse imp']);
    });

    test('暂停（看不到的页面）的时候不查；继续再查。cancel 之后不再查', () async {
      final api = FakeApi(timeout: const Duration(seconds: 10))..claimedAt = DateTime.now();
      final seen = <ImportStatus>[];
      final sub = api.watchImport('imp').listen((i) => seen.add(i.status), onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(api.polls, greaterThan(1));
      sub.pause();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final paused = api.polls;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(api.polls, paused, reason: '暂停的时候不查');
      api.statuses.add(ImportStatus.review);
      sub.resume();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(seen.last, ImportStatus.review);

      final api2 = FakeApi(timeout: const Duration(seconds: 10))..claimedAt = DateTime.now();
      final sub2 = api2.watchImport('imp').listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub2.cancel();
      final stopped = api2.polls;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(api2.polls, stopped);
    });
  });

  group('importNeedsRestart（跟 parse-price-list 重跑的规则一样）', () {
    final now = DateTime.utc(2026, 11, 25, 10);
    PriceListImport imp({required Duration age, Duration? claimedAgo, ImportStatus status = ImportStatus.processing}) =>
        PriceListImport(
          id: 'i',
          wholesalerId: 'w',
          filePath: 'w/x.jpg',
          fileType: ImportFileType.image,
          status: status,
          aiRaw: claimedAgo == null ? null : {'claimed_at': now.subtract(claimedAgo).toIso8601String()},
          createdAt: now.subtract(age),
        );

    test('还没人开始读：刚建好不算，超过 30 秒算', () {
      expect(importNeedsRestart(imp(age: const Duration(seconds: 5)), now: now), isFalse);
      expect(importNeedsRestart(imp(age: const Duration(minutes: 1)), now: now), isTrue);
    });

    test('有人在读：10 分钟内不算，超过算（worker 死掉了）', () {
      expect(
        importNeedsRestart(
          imp(age: const Duration(hours: 1), claimedAgo: const Duration(minutes: 9)),
          now: now,
        ),
        isFalse,
      );
      expect(
        importNeedsRestart(
          imp(age: const Duration(hours: 1), claimedAgo: const Duration(minutes: 11)),
          now: now,
        ),
        isTrue,
      );
    });

    test('读完的不算', () {
      for (final s in [ImportStatus.review, ImportStatus.failed, ImportStatus.applied]) {
        expect(
          importNeedsRestart(
            imp(age: const Duration(hours: 1), status: s),
            now: now,
          ),
          isFalse,
        );
      }
    });
  });

  group('onRejoined（Realtime 断线重连后补刷新）', () {
    test('第一次连上不叫；之后每一次重新连上都叫；其他状态不管', () {
      var n = 0;
      final cb = onRejoined(() => n++);
      cb(RealtimeSubscribeStatus.subscribed, null);
      expect(n, 0);
      cb(RealtimeSubscribeStatus.channelError, null);
      cb(RealtimeSubscribeStatus.timedOut, null);
      expect(n, 0);
      cb(RealtimeSubscribeStatus.subscribed, null);
      cb(RealtimeSubscribeStatus.subscribed, null);
      expect(n, 2);
    });

    test('等太久 → IMPORT_TIMEOUT', () async {
      final api = FakeApi(); // 永远 processing
      expect(
        api.watchImport('imp').drain<void>(),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'IMPORT_TIMEOUT')),
      );
    });
  });

  group('submitPriceList', () {
    test('照片：按内容判断成 JPEG，上传 → 建导入 → 叫 AI', () async {
      final api = FakeApi();
      final imp = await api.submitPriceList('w1', jpeg, fileName: 'IMG_0001.HEIC');
      expect(imp.status, ImportStatus.processing);
      expect(api.calls, ['upload jpg image/jpeg', 'create w1/abc.jpg image', 'parse imp-1']);
    });

    test('不收的格式、太大：不上传', () async {
      final api = FakeApi();
      final heic = Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63, 0, 0, 0, 0]);
      await expectLater(
        api.submitPriceList('w1', heic),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'UNSUPPORTED_FILE').having((e) => e.detail, 'detail', 'heic'),
        ),
      );
      await expectLater(
        api.submitPriceList('w1', Uint8List(priceListMaxBytes + 1)),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'FILE_TOO_LARGE')),
      );
      expect(api.calls, isEmpty);
    });

    test('叫不到 AI：导入标成失败（记下真正的原因），错误照样丢给页面', () async {
      for (final (code, reason) in [('NETWORK', 'NETWORK'), ('AUTH', 'AUTH'), ('CONFIG_MISSING', 'START_FAILED')]) {
        final api = FakeApi()..startParseError = AppError(code);
        await expectLater(
          api.submitPriceList('w1', jpeg),
          throwsA(isA<AppError>().having((e) => e.code, 'code', code)),
        );
        expect(api.calls.last, 'failed imp-1 $reason');
      }
    });

    test('没网络，但 AI 其实已经开始读了（202 在路上断了）：不标成失败，照常等那一份', () async {
      final api = FakeApi()
        ..startParseError = const AppError('NETWORK')
        ..markMisses = true
        ..claimedAt = DateTime.now();
      final imp = await api.submitPriceList('w1', jpeg);
      expect(imp.claimedAt, isNotNull);
      expect(imp.status, ImportStatus.processing);
      expect(api.calls.last, 'failed imp-1 NETWORK', reason: '只标没人读过的（ai_raw 是空的）');
      // 标不到、也没人在读（例如已经被别人标成失败）：照样说没网络
      final gone = FakeApi()
        ..startParseError = const AppError('NETWORK')
        ..markMisses = true;
      await expectLater(
        gone.submitPriceList('w1', jpeg),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'NETWORK')),
      );
    });

    test('停权、用量满了、暂时叫不到：这一次当作没传过（删掉导入和档案，不留一份「读不到」），错误照样丢给页面', () async {
      for (final code in ['WHOLESALER_SUSPENDED', 'TOO_MANY_IMPORTS', 'QUOTA_UNAVAILABLE']) {
        final api = FakeApi()..startParseError = AppError(code);
        await expectLater(
          api.submitPriceList('w1', jpeg),
          throwsA(isA<AppError>().having((e) => e.code, 'code', code)),
        );
        expect(api.calls, [
          'upload jpg image/jpeg',
          'create w1/abc.jpg image',
          'parse imp-1',
          'discard imp-1 w1/abc.jpg',
        ]);
      }
      // 删不掉（没网络）：标成失败，首页才不会一直显示「AI 在读」
      final offline = FakeApi()
        ..startParseError = const AppError('WHOLESALER_SUSPENDED')
        ..discardError = const AppError('NETWORK');
      await expectLater(offline.submitPriceList('w1', jpeg), throwsA(isA<AppError>()));
      expect(offline.calls.last, 'failed imp-1 START_FAILED');
    });

    test('用量满了：等 retry_after 之前再传，直接说还要等几分钟，不再上传（不会多一个档案、一份导入）', () async {
      final api = FakeApi()..startParseError = const AppError('TOO_MANY_IMPORTS', detail: '480');
      await expectLater(api.submitPriceList('w1', jpeg), throwsA(isA<AppError>()));
      api.calls.clear();
      await expectLater(
        api.submitPriceList('w1', jpeg),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', 'TOO_MANY_IMPORTS')
              .having((e) => e.retryAfter!.inSeconds, 'retryAfter', inInclusiveRange(470, 480)),
        ),
      );
      expect(api.calls, isEmpty, reason: '没上传、没建导入');
      // 别家批发商不受影响
      api.startParseError = null;
      await api.submitPriceList('w2', jpeg);
      expect(api.calls, contains('parse imp-1'));
    });

    test('别人已经叫了 AI（409 IMPORT_ALREADY_RUNNING）：一样在读，不算失败', () async {
      final api = FakeApi()..startParseError = const AppError('IMPORT_ALREADY_RUNNING');
      final imp = await api.submitPriceList('w1', jpeg);
      expect(imp.status, ImportStatus.processing);
      expect(api.calls.last, 'parse imp-1');
    });
  });

  group('上传前检查', () {
    final heic = Uint8List.fromList([0, 0, 0, 0x18, ...'ftypheic'.codeUnits, 0, 0, 0, 0]);
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0]);
    final pdf = Uint8List.fromList('%PDF-1.7\n'.codeUnits);

    test('价目表：按内容判断，不信档名', () {
      expect(checkPriceListFile(jpeg, fileName: 'IMG_0001.HEIC'), FileKind.jpeg);
      expect(checkPriceListFile(pdf, fileName: 'list.xlsx'), FileKind.pdf);
      expect(
        () => checkPriceListFile(heic, fileName: 'IMG_0001.jpg'),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'UNSUPPORTED_FILE').having((e) => e.detail, 'detail', 'heic'),
        ),
      );
      expect(
        () => checkPriceListFile(Uint8List.fromList([1, 2, 3, 0, 4])),
        throwsA(isA<AppError>().having((e) => e.detail, 'detail', 'unknown')),
      );
      expect(
        () => checkPriceListFile(Uint8List(priceListMaxBytes + 1)),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'FILE_TOO_LARGE')),
      );
    });

    test('照片超过 7 MB（parse-price-list 收不了）：上传前就挡，detail 是 image；PDF 一样可以到 10 MB', () {
      final big = Uint8List(priceListMaxImageBytes + 1)..setAll(0, png);
      expect(
        () => checkPriceListFile(big),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'FILE_TOO_LARGE').having((e) => e.detail, 'detail', 'image'),
        ),
      );
      expect(checkPriceListFile(Uint8List(priceListMaxImageBytes)..setAll(0, png)), FileKind.png);
      final bigPdf = Uint8List(priceListMaxImageBytes + 1)..setAll(0, pdf);
      expect(checkPriceListFile(bigPdf), FileKind.pdf);
    });

    test('商品照片：只收 JPEG / PNG / WebP，最多 5 MB', () {
      expect(checkProductPhoto(jpeg), FileKind.jpeg);
      expect(checkProductPhoto(png), FileKind.png);
      for (final bad in [heic, pdf]) {
        expect(
          () => checkProductPhoto(bad),
          throwsA(isA<AppError>().having((e) => e.code, 'code', 'UNSUPPORTED_FILE')),
        );
      }
      final big = Uint8List(productPhotoMaxBytes + 1)..setAll(0, jpeg);
      expect(() => checkProductPhoto(big), throwsA(isA<AppError>().having((e) => e.code, 'code', 'FILE_TOO_LARGE')));
    });
  });

  group('送出去的请求', () {
    test('选 WhatsApp：先记同意、再改通知方式（第二步断线也不会变成「WhatsApp 没同意」= 什么通知都不发）', () async {
      final r = Recorder();
      await r.api.setNotifyChannel('w1', NotifyChannel.whatsapp);
      expect(r.requests.take(2), [
        'PATCH /rest/v1/wholesalers?id=eq.w1&whatsapp_opt_in_at=is.null',
        'PATCH /rest/v1/wholesalers?id=eq.w1&select=id',
      ]);

      // 记同意之后断线：通知方式没改（还是原本的），错误丢给页面
      final cut = Recorder()..failAt = 1;
      await expectLater(
        cut.api.setNotifyChannel('w1', NotifyChannel.whatsapp),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'NETWORK')),
      );
      expect(cut.requests.first, contains('whatsapp_opt_in_at=is.null'));

      // 其他方式不用同意
      final push = Recorder();
      await push.api.setNotifyChannel('w1', NotifyChannel.push);
      expect(push.requests.first, 'PATCH /rest/v1/wholesalers?id=eq.w1&select=id');
    });

    test('标成失败只标没人读过的（ai_raw 是空的）；删导入也是，删到了才删档案', () async {
      final r = Recorder();
      expect(await r.api.markImportFailed('i1', 'NETWORK'), isTrue);
      expect(
        r.requests.single,
        'PATCH /rest/v1/price_list_imports?id=eq.i1&status=eq.processing&ai_raw=is.null&select=id',
      );

      final d = Recorder();
      final imp = PriceListImport(
        id: 'i1',
        wholesalerId: 'w1',
        filePath: 'w1/abc.jpg',
        fileType: ImportFileType.image,
        status: ImportStatus.processing,
        createdAt: DateTime(2026),
      );
      expect(await d.api.discardImport(imp), isTrue);
      expect(d.requests, [
        'DELETE /rest/v1/price_list_imports?id=eq.i1&status=eq.processing&ai_raw=is.null&select=id',
        'DELETE /storage/v1/object/price-lists?',
      ]);
    });

    test('老板换语言：批发商、店铺的通知语言也换（一样的不写）', () async {
      final r = Recorder();
      await r.api.setBusinessLocale('ms', wholesalerIds: ['w1'], shopIds: ['s1']);
      expect(r.requests, [
        'PATCH /rest/v1/wholesalers?id=eq.w1&locale=neq.ms',
        'PATCH /rest/v1/shops?id=eq.s1&locale=neq.ms',
      ]);
    });
  });

  test('updateImportRow 只能改批发商可以改的字段（不准改的不会送出去）', () async {
    await expectLater(
      FakeApi().updateImportRow('r', {'import_id': 'other', 'name': 'x'}),
      throwsA(
        isA<AppError>()
            .having((e) => e.code, 'code', 'UNKNOWN')
            .having((e) => e.message, 'message', contains('not editable: import_id')),
      ),
    );
    // 对照：可以改的字段真的会送出去（FakeApi 连不到服务器 → NETWORK），所以上面不是因为连不到才失败
    await expectLater(
      FakeApi().updateImportRow('r', {'name': 'x', 'matched_product_id': null}),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'NETWORK')),
    );
  });
}
