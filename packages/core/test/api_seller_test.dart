// WholesaleApi 批发商端不连服务器也能测的部分：错误代码、等 AI 读完、上传前的检查
import 'dart:typed_data';

import 'package:supabase/supabase.dart';
import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

class FakeApi extends WholesaleApi {
  FakeApi() : super(SupabaseClient('http://127.0.0.1:1', 'test-key'));

  final calls = <String>[];
  final statuses = <Object>[]; // ImportStatus 或 AppError，一次 getImport 用一个
  Object? startParseError;

  @override
  Duration get importPollInterval => const Duration(milliseconds: 1);

  @override
  Duration get importPollTimeout => const Duration(milliseconds: 200);

  @override
  Future<PriceListImport> getImport(String importId) async {
    final next = statuses.isEmpty ? ImportStatus.processing : statuses.removeAt(0);
    if (next is AppError) throw next;
    return PriceListImport(
      id: importId,
      wholesalerId: 'w',
      filePath: 'w/x.jpg',
      fileType: ImportFileType.image,
      status: next as ImportStatus,
      createdAt: DateTime(2026),
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

  @override
  Future<void> markImportFailed(String importId, String code) async => calls.add('failed $importId $code');
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
      expect(AppError.fromFunction(const FunctionsFetchException(details: AuthException('expired'))).code, 'AUTH');
      expect(AppError.fromFunction(const FunctionsRelayException(status: 502)).code, 'UNKNOWN');
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

    test('其他错误直接丢出来', () async {
      final api = FakeApi()..statuses.add(const AppError('IMPORT_NOT_FOUND'));
      expect(
        api.watchImport('imp').toList(),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'IMPORT_NOT_FOUND')),
      );
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

    test('叫不到 AI：导入标成失败，错误照样丢给页面', () async {
      final api = FakeApi()..startParseError = const AppError('NETWORK');
      await expectLater(
        api.submitPriceList('w1', jpeg),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'NETWORK')),
      );
      expect(api.calls.last, 'failed imp-1 START_FAILED');
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

  test('updateImportRow 只能改批发商可以改的字段', () {
    expect(() => FakeApi().updateImportRow('r', {'import_id': 'other'}), throwsA(isA<AppError>()));
  });
}
