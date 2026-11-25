// 真的手机那一层（PlatformSellerDevice）：把 image_picker / file_picker 的 platform 换成假的，检查
// - 照片缩小时宽、高都给（直的照片长边也不会超过）
// - Android 选价目表时 App 被关掉：重新打开拿回选到的照片 / 文件（只拿一次；商品照片不拿；
//   记着是从哪一个选的，不会拿到 image_picker 留着的旧照片）
import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:jb_wholesale/features/seller/seller_device.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholesale_core/wholesale_core.dart';

class FakeImagePicker extends ImagePickerPlatform {
  ImageSource? source;
  ImagePickerOptions? options;
  XFile? next;
  Object? error;

  /// 选的时候 SharedPreferences 里记着在选什么
  String? pendingWhilePicking;
  LostDataResponse lost = LostDataResponse.empty();
  int lostCalls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    this.source = source;
    this.options = options;
    pendingWhilePicking = (await SharedPreferences.getInstance()).getString(PlatformSellerDevice.pendingPickKey);
    if (error != null) throw error!;
    return next;
  }

  @override
  Future<LostDataResponse> getLostData() async {
    lostCalls++;
    final l = lost;
    lost = LostDataResponse.empty(); // 只拿得到一次
    return l;
  }
}

class FakeFilePickerAndroid extends FilePickerAndroid {
  LostFilePickerResult? lost;

  @override
  Future<LostFilePickerResult?> retrieveLostData() async {
    final l = lost;
    lost = null;
    return l;
  }
}

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(32, 1)]);
final pdf = Uint8List.fromList('%PDF-1.7\n'.codeUnits);

/// 另一张照片（XFile.fromData 在手机上没有档名，用内容分）
final jpeg2 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, ...List.filled(16, 2)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeImagePicker images;
  late FakeFilePickerAndroid files;
  const device = PlatformSellerDevice();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    images = FakeImagePicker();
    files = FakeFilePickerAndroid();
    ImagePickerPlatform.instance = images;
    FilePickerPlatform.instance = files;
  });

  Future<String?> pending() async =>
      (await SharedPreferences.getInstance()).getString(PlatformSellerDevice.pendingPickKey);

  test('拍照：宽、高都限 2576（直的照片 3000×4000 也是长边 2576），选的时候记着在选价目表，选完就清掉', () async {
    images.next = XFile.fromData(jpeg, name: 'image_picker_1.jpg');
    final f = await device.pickImage(
      PickSource.camera,
      purpose: PickPurpose.priceList,
      maxSide: 2576,
      imageQuality: 85,
    );
    expect(images.source, ImageSource.camera);
    expect((images.options!.maxWidth, images.options!.maxHeight, images.options!.imageQuality), (2576, 2576, 85));
    expect(images.pendingWhilePicking, 'priceList:image');
    expect(await pending(), isNull);
    expect(await f!.readAsBytes(), jpeg);

    await device.pickImage(PickSource.gallery, purpose: PickPurpose.productPhoto, maxSide: 1600);
    expect((images.options!.maxWidth, images.options!.maxHeight), (1600, 1600));
    expect(images.pendingWhilePicking, 'productPhoto');
  });

  test('不准用相机：NO_PERMISSION，也清掉记号', () async {
    images.error = PlatformException(code: 'camera_access_denied');
    await expectLater(
      device.pickImage(PickSource.camera, purpose: PickPurpose.priceList),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'NO_PERMISSION')),
    );
    expect(await pending(), isNull);
  });

  test('选价目表照片时 App 被关掉（记号还在）：拿回那张照片，只拿一次', () async {
    SharedPreferences.setMockInitialValues({PlatformSellerDevice.pendingPickKey: 'priceList:image'});
    images.lost = LostDataResponse(
      file: XFile.fromData(jpeg, name: 'lost.jpg'),
      type: RetrieveType.image,
    );
    final f = await device.recoverLostPriceList();
    expect(f, isNotNull);
    expect(f!.size, jpeg.length);
    expect(await f.readAsBytes(), jpeg);
    expect(await pending(), isNull);
    expect(await device.recoverLostPriceList(), isNull, reason: '只拿一次');
  });

  test('选文件时 App 被关掉：从 file_picker 拿回那个文件', () async {
    SharedPreferences.setMockInitialValues({PlatformSellerDevice.pendingPickKey: 'priceList:file'});
    files.lost = LostFilePickerResult(
      files: [
        AndroidPlatformFile(
          name: 'price.pdf',
          uri: Uri.parse('content://downloads/price.pdf'),
          xFile: XFile.fromData(pdf, name: 'price.pdf'),
          bytesLength: pdf.length,
        ),
      ],
    );
    final f = await device.recoverLostPriceList();
    expect((f!.name, f.size), ('price.pdf', pdf.length));
    expect(await f.readAsBytes(), pdf);
  });

  test('上一次选完了（没有记号）、或是选商品照片：不拿（商品那一页填的资料已经不见了）', () async {
    images.lost = LostDataResponse(file: XFile.fromData(jpeg, name: 'lost.jpg'));
    expect(await device.recoverLostPriceList(), isNull);
    expect(images.lostCalls, 0);

    SharedPreferences.setMockInitialValues({PlatformSellerDevice.pendingPickKey: 'productPhoto'});
    expect(await device.recoverLostPriceList(), isNull);
    expect(images.lostCalls, 1, reason: '商品照片不用，但要拿出来清掉（不然之后会被当成价目表）');
    expect(images.lost.isEmpty, isTrue);
    expect(await pending(), isNull);
  });

  test('拍商品照片时被关掉、之后选价目表文件时又被关掉：拿回的是那个文件，不是 image_picker 留着的旧照片', () async {
    // image_picker 留着一张商品照片（旧版本没有清掉），file_picker 留着老板选的 PDF
    SharedPreferences.setMockInitialValues({PlatformSellerDevice.pendingPickKey: 'priceList:file'});
    images.lost = LostDataResponse(
      file: XFile.fromData(jpeg, name: 'product.jpg'),
      type: RetrieveType.image,
    );
    files.lost = LostFilePickerResult(
      files: [
        AndroidPlatformFile(
          name: 'price.pdf',
          uri: Uri.parse('content://downloads/price.pdf'),
          xFile: XFile.fromData(pdf, name: 'price.pdf'),
          bytesLength: pdf.length,
        ),
      ],
    );
    final f = await device.recoverLostPriceList();
    expect(f!.name, 'price.pdf');
    expect(await f.readAsBytes(), pdf);
    expect(images.lost.isEmpty, isTrue, reason: '旧照片也清掉了');

    // 照片那边被关掉：拿照片，file_picker 留着的旧文件不要
    SharedPreferences.setMockInitialValues({PlatformSellerDevice.pendingPickKey: 'priceList:image'});
    images.lost = LostDataResponse(
      file: XFile.fromData(jpeg2, name: 'list.jpg'),
      type: RetrieveType.image,
    );
    files.lost = LostFilePickerResult(
      files: [
        AndroidPlatformFile(
          name: 'old.pdf',
          uri: Uri.parse('content://downloads/old.pdf'),
          xFile: XFile.fromData(pdf, name: 'old.pdf'),
          bytesLength: pdf.length,
        ),
      ],
    );
    expect(await (await device.recoverLostPriceList())!.readAsBytes(), jpeg2);
    expect(files.lost, isNull, reason: '旧文件也清掉了');
  });

  test('旧版本的记号（只有 priceList）：先看照片、再看文件', () async {
    SharedPreferences.setMockInitialValues({PlatformSellerDevice.pendingPickKey: 'priceList'});
    files.lost = LostFilePickerResult(
      files: [
        AndroidPlatformFile(
          name: 'price.pdf',
          uri: Uri.parse('content://downloads/price.pdf'),
          xFile: XFile.fromData(pdf, name: 'price.pdf'),
          bytesLength: pdf.length,
        ),
      ],
    );
    expect((await device.recoverLostPriceList())!.name, 'price.pdf');
    SharedPreferences.setMockInitialValues({PlatformSellerDevice.pendingPickKey: 'priceList'});
    images.lost = LostDataResponse(
      file: XFile.fromData(jpeg2, name: 'lost.jpg'),
      type: RetrieveType.image,
    );
    expect(await (await device.recoverLostPriceList())!.readAsBytes(), jpeg2);
  });

  test('拿回来时是错误（例如不准用照片）：照样说清楚', () async {
    SharedPreferences.setMockInitialValues({PlatformSellerDevice.pendingPickKey: 'priceList:image'});
    images.lost = LostDataResponse(exception: PlatformException(code: 'photo_access_denied'));
    await expectLater(
      device.recoverLostPriceList(),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'NO_PERMISSION')),
    );
  });
}
