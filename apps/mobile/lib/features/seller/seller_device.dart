import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
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

/// 批发商端用到手机功能的地方：拍照 / 选照片 / 选文件、分享文字、打印 PDF。
/// 集中在这里，测试换成假的（不会碰到 platform channel）
abstract class SellerDevice {
  /// 拍照 / 选照片。image_picker 会缩小并转成 JPEG（iPhone 的 HEIC 也会转），按取消回传 null
  Future<PickedFile?> pickImage(PickSource source, {double maxWidth = 2576, int imageQuality = 85});

  /// 选文件（file_picker 13 的静态 API），按取消回传 null
  Future<PickedFile?> pickFile({required List<String> extensions});

  /// 分享一段文字（WhatsApp 给送货员……）。[origin] 是按钮的位置（iPad 一定要有）
  Future<void> shareText(String text, {String? subject, Rect? origin});

  /// 打开系统的打印画面；[build] 按选好的纸张做 PDF
  Future<void> printPdf({required String name, required Future<Uint8List> Function(PdfPageFormat format) build});
}

/// 真的手机：image_picker、file_picker、share_plus、printing（网页版也可以用）
class PlatformSellerDevice implements SellerDevice {
  const PlatformSellerDevice();

  @override
  Future<PickedFile?> pickImage(PickSource source, {double maxWidth = 2576, int imageQuality = 85}) async {
    final XFile? x;
    try {
      x = await ImagePicker().pickImage(
        source: source == PickSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: maxWidth,
        imageQuality: imageQuality,
      );
    } on PlatformException catch (e) {
      // camera_access_denied / photo_access_denied：老板拒绝了权限
      throw AppError(e.code.contains('access_denied') ? 'NO_PERMISSION' : 'UNKNOWN', message: e.message);
    }
    if (x == null) return null;
    return PickedFile(name: x.name, size: await x.length(), read: x.readAsBytes);
  }

  @override
  Future<PickedFile?> pickFile({required List<String> extensions}) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions);
    if (f == null) return null;
    return PickedFile(name: f.name, size: f.lengthSync() ?? await f.length(), read: f.readAsBytes);
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
