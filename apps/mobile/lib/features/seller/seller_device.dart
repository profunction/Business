import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wholesale_core/wholesale_core.dart';

/// 选到的档案（照片或文件）。[size] 先知道的话，太大的不用读进来就可以拒绝
class PickedFile {
  PickedFile({this.name, this.size, required this.read});

  /// 测试 / 示范用：内容已经在记忆体里
  factory PickedFile.memory(Uint8List bytes, {String? name}) =>
      PickedFile(name: name, size: bytes.length, read: () async => bytes);

  /// 原本的档名（只用来帮忙认 CSV，真正的格式看内容）
  final String? name;
  final int? size;

  /// 读出内容（大的档案先看 [size]，不要急着读）
  final Future<Uint8List> Function() read;

  Future<Uint8List> readAsBytes() => read();
}

/// 价目表、商品照片可以从哪里来
enum PickSource { camera, gallery, file }

/// 选照片 / 文件是要做什么（Android 把 App 关掉再打开时，只有价目表要拿回来）
enum PickPurpose { priceList, productPhoto }

/// 批发商端用到手机功能的地方：拍照 / 选照片 / 选文件、分享文字、打印 PDF。
/// 集中在这里，测试换成假的（不会碰到 platform channel）
abstract class SellerDevice {
  /// 拍照 / 选照片。image_picker 会缩小到长边（宽、高都）最多 [maxSide]、转成 JPEG（iPhone 的 HEIC 也会转），
  /// 按取消回传 null
  Future<PickedFile?> pickImage(
    PickSource source, {
    required PickPurpose purpose,
    double maxSide = 2576,
    int imageQuality = 85,
  });

  /// 选文件（file_picker 13 的静态 API），按取消回传 null。只有价目表会选文件
  Future<PickedFile?> pickFile({required List<String> extensions});

  /// Android：选价目表（拍照、选照片、选文件）的时候系统把 App 关掉了（便宜的手机记忆体不够、开着相机），
  /// App 重新打开后拿回那一次选到的。只拿得到一次；没有、或那一次不是选价目表 → null。其他手机不会发生
  Future<PickedFile?> recoverLostPriceList();

  /// 分享一段文字（WhatsApp 给送货员……）。[origin] 是按钮的位置（iPad 一定要有）
  Future<void> shareText(String text, {String? subject, Rect? origin});

  /// 打开系统的打印画面；[build] 按选好的纸张做 PDF
  Future<void> printPdf({required String name, required Future<Uint8List> Function(PdfPageFormat format) build});
}

/// 真的手机：image_picker、file_picker、share_plus、printing（网页版也可以用）
class PlatformSellerDevice implements SellerDevice {
  const PlatformSellerDevice();

  /// 正在选（还没回来）的是什么：'priceList:image'（拍照 / 选照片）、'priceList:file'（选文件）、'productPhoto'。
  /// App 被关掉的话这个会留着，重新打开时才知道要不要拿回来、从哪一个拿
  static const pendingPickKey = 'seller_pending_pick';

  static String _pending(PickPurpose purpose, {required bool file}) =>
      purpose == PickPurpose.priceList ? '${purpose.name}:${file ? 'file' : 'image'}' : purpose.name;

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Android：选之前记下在选什么（[pending]），选完（不管有没有选到）就清掉
  Future<T> _remember<T>(String pending, Future<T> Function() pick) async {
    if (!_isAndroid) return pick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingPickKey, pending);
    try {
      return await pick();
    } finally {
      await prefs.remove(pendingPickKey);
    }
  }

  static AppError _pickError(PlatformException e) =>
      // camera_access_denied / photo_access_denied：老板拒绝了权限
      AppError(e.code.contains('access_denied') ? 'NO_PERMISSION' : 'UNKNOWN', message: e.message);

  static Future<PickedFile> _fromXFile(XFile x) async =>
      PickedFile(name: x.name, size: await x.length(), read: x.readAsBytes);

  static Future<PickedFile> _fromPlatformFile(PlatformFile f) async =>
      PickedFile(name: f.name, size: f.lengthSync() ?? await f.length(), read: f.readAsBytes);

  @override
  Future<PickedFile?> pickImage(
    PickSource source, {
    required PickPurpose purpose,
    double maxSide = 2576,
    int imageQuality = 85,
  }) => _remember(_pending(purpose, file: false), () async {
    final XFile? x;
    try {
      // 宽和高都要给：只给宽的话，直的照片长边会超过 maxSide（image_picker 只按给的那一边缩）
      x = await ImagePicker().pickImage(
        source: source == PickSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: maxSide,
        maxHeight: maxSide,
        imageQuality: imageQuality,
      );
    } on PlatformException catch (e) {
      throw _pickError(e);
    }
    return x == null ? null : _fromXFile(x);
  });

  @override
  Future<PickedFile?> pickFile({required List<String> extensions}) =>
      _remember(_pending(PickPurpose.priceList, file: true), () async {
        final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions);
        return f == null ? null : _fromPlatformFile(f);
      });

  @override
  Future<PickedFile?> recoverLostPriceList() async {
    if (!_isAndroid) return null;
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(pendingPickKey);
    if (pending == null) return null; // 上一次选完了（没有被关掉）
    await prefs.remove(pendingPickKey);
    // 两个 plugin 留着的都拿出来（拿了就清掉）：image_picker 留着的照片要等下一次拍照才会清掉，
    // 不拿的话，之后选文件时被关掉，会拿到这张旧照片（例如商品照片）当成价目表上传。
    // 只有要用的那一个才读档案（不用的旧照片可能已经被删掉了）
    final image = await ImagePicker().retrieveLostData();
    final files = FilePickerPlatform.instance;
    final file = files is FilePickerAndroid ? await files.retrieveLostData() : null;
    final hasImage =
        !image.isEmpty && (image.exception != null || image.file != null || (image.files ?? const []).isNotEmpty);
    final useImage = switch (pending) {
      'priceList:image' => true,
      'priceList:file' => false,
      // 旧版本只记 'priceList'：不知道是哪一个，先看照片再看文件
      'priceList' => hasImage,
      _ => null, // 商品照片：那一页填的资料已经不见了，不用拿回来
    };
    if (useImage == null) return null;
    if (useImage) {
      if (!hasImage) return null;
      final e = image.exception;
      if (e != null) throw _pickError(e);
      return _fromXFile(image.file ?? image.files!.first);
    }
    final e = file?.exception;
    if (e != null) throw _pickError(e);
    final f = file?.files.firstOrNull;
    return f == null ? null : _fromPlatformFile(f);
  }

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject, sharePositionOrigin: origin));
  }

  @override
  Future<void> printPdf({required String name, required Future<Uint8List> Function(PdfPageFormat format) build}) async {
    await Printing.layoutPdf(name: name, format: PdfPageFormat.a4, onLayout: build);
  }
}

/// 测试里换成假的
final sellerDeviceProvider = Provider<SellerDevice>((ref) => const PlatformSellerDevice());
