import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../app/seller_providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'seller_device.dart';
import 'seller_widgets.dart';

/// 选文件时让老板选的格式（file_picker 的 allowedExtensions）
const priceListExtensions = ['pdf', 'xlsx', 'xls', 'csv'];

/// 上传之前先检查（太大 / 照片超过 7 MB / HEIC / 看不懂的格式），回传要上传的内容。不对就丢 AppError（l.error 有三语说明）
Future<({Uint8List bytes, FileKind kind})> readPriceListFile(PickedFile file) async {
  // 知道大小的话，太大的不用读进来
  if ((file.size ?? 0) > priceListMaxBytes) throw const AppError('FILE_TOO_LARGE');
  final bytes = await file.readAsBytes();
  final kind = checkPriceListFile(bytes, fileName: file.name);
  return (bytes: bytes, kind: kind);
}

enum _Stage { choose, uploading, waiting, failed, timedOut }

/// 上传价目表：三个大按钮「拍照」「选照片」「选文件（Excel、PDF）」→ 上传 → 等 AI（每 3 秒查一次，最多 5 分钟）
/// → 读好了去确认页；读不到就说原因，可以再上传一次。[importId] 有给的话直接等那一份（从首页回来看）。
/// 等的时候（还有等太久的时候）可以「上传另一份」：那一份卡住了、传错了，都不会被困住
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.importId, this.recovered});

  final String? importId;

  /// Android 把 App 关掉之前选到的价目表（首页拿回来的）：打开就直接上传
  final PickedFile? recovered;

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  _Stage _stage = _Stage.choose;
  StreamSubscription<PriceListImport>? _watch;
  DateTime? _startedAt;
  bool _slow = false;

  /// 失败的原因（三语文字）
  String? _failure;

  /// 失败画面的标题：AI 读不到，或查不到进度（没权限、找不到那一份……）
  String? _failureTitle;

  @override
  void initState() {
    super.initState();
    final id = widget.importId;
    final recovered = widget.recovered;
    if (id != null && isUuid(id)) {
      _wait(id);
    } else if (recovered != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showMessage(context, context.l10n.sellerImportRecovered);
        _submit(recovered);
      });
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _pick(PickSource source) async {
    final l = context.l10n;
    final device = ref.read(sellerDeviceProvider);
    try {
      final file = source == PickSource.file
          ? await device.pickFile(extensions: priceListExtensions)
          // 照片：image_picker 缩小到长边 2576（AI 最划算的大小），转成 JPEG（HEIC 也会转）
          : await device.pickImage(source, purpose: PickPurpose.priceList, maxSide: 2576, imageQuality: 85);
      if (file == null || !mounted) return;
      await _submit(file);
    } catch (e) {
      // 不准用相机……：留在这一页，说一句话就好
      if (mounted) showMessage(context, l.error(e), error: true);
    }
  }

  /// 检查 → 上传 → 叫 AI → 等
  Future<void> _submit(PickedFile file) async {
    final l = context.l10n;
    try {
      final picked = await readPriceListFile(file);
      if (!mounted) return;
      setState(() => _stage = _Stage.uploading);
      final import = await ref.read(sellerActionsProvider).submitPriceList(picked.bytes, fileName: file.name);
      if (mounted) _wait(import.id);
    } catch (e) {
      // HEIC、太大、上传不了……：留在这一页，说一句话就好
      if (!mounted) return;
      setState(() => _stage = _Stage.choose);
      showMessage(context, l.error(e), error: true);
    }
  }

  /// 不等这一份了（卡住了、传错了）：回到三个大按钮，上传另一份。新的那一份会变成首页显示的「最近一次」
  void _chooseAnother() {
    _watch?.cancel();
    _watch = null;
    setState(() {
      _stage = _Stage.choose;
      _failure = null;
      _failureTitle = null;
    });
  }

  /// 等 AI 读完：review → 确认页；failed → 原因
  void _wait(String importId) {
    _watch?.cancel();
    setState(() {
      _stage = _Stage.waiting;
      _startedAt = DateTime.now();
      _slow = false;
    });
    _watch = ref
        .read(apiProvider)
        .watchImport(importId)
        .listen(
          (imp) {
            if (!mounted) return;
            switch (imp.status) {
              case ImportStatus.processing:
                // 超过一分钟：告诉老板还在读（长的价目表要久一点）
                final slow = DateTime.now().difference(_startedAt!) > const Duration(minutes: 1);
                if (slow != _slow) setState(() => _slow = slow);
              case ImportStatus.review:
                ref.invalidate(sellerHomeProvider);
                context.pushReplacement('/seller/import/${imp.id}');
              case ImportStatus.failed:
                ref.invalidate(sellerHomeProvider);
                _fail(context.l10n.importFailure(imp.errorMessage, fileType: imp.fileType));
              case ImportStatus.applied:
                context.pushReplacement('/seller/import/${imp.id}');
            }
          },
          onError: (Object e) {
            if (!mounted) return;
            // 等了 5 分钟还没读完：不算失败（AI 还在读，卡住的已经再叫过一次），请老板晚一点从首页回来看
            if (e is AppError && e.code == 'IMPORT_TIMEOUT') {
              setState(() => _stage = _Stage.timedOut);
            } else {
              // 查不到进度（找不到那一份、没权限、登录过期）：不是 AI 读不到
              _fail(context.l10n.error(e), title: context.l10n.sellerImportCheckFailed);
            }
          },
        );
  }

  void _fail(String reason, {String? title}) => setState(() {
    _stage = _Stage.failed;
    _failure = reason;
    _failureTitle = title;
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.sellerHomeImport)),
      body: switch (_stage) {
        _Stage.choose => _choose(context),
        _Stage.uploading => _progress(context, l.sellerImportUploading, null),
        _Stage.waiting => _progress(
          context,
          _slow ? l.sellerImportStillReading : l.sellerImportProcessing,
          l.sellerImportWaitHint,
        ),
        _Stage.timedOut => CenterMessage(
          key: const Key('import-timeout'),
          icon: Icons.hourglass_bottom,
          text: l.sellerErrImportTimeout,
        ),
        _Stage.failed => CenterMessage(
          key: const Key('import-failed'),
          icon: Icons.error_outline,
          iconColor: AppTheme.problem,
          text: _failureTitle ?? l.sellerImportFailedTitle,
          detail: _failure,
        ),
      },
      bottomNavigationBar: switch (_stage) {
        _Stage.failed => BottomAction(
          child: FilledButton.icon(
            key: const Key('import-retry'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _stage = _Stage.choose),
            label: Text(l.sellerImportRetry),
          ),
        ),
        // 等的时候可以先回首页做别的事（读好了首页会显示）；这一份不要了也可以上传另一份
        _Stage.waiting || _Stage.timedOut => BottomAction(
          above: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TextButton.icon(
              key: const Key('import-upload-other'),
              icon: const Icon(Icons.upload_file),
              onPressed: _chooseAnother,
              label: Text(l.sellerImportUploadOther, textAlign: TextAlign.center),
            ),
          ),
          child: OutlinedButton(
            key: const Key('import-leave'),
            onPressed: () => context.go('/seller'),
            child: Text(l.sellerBackHome),
          ),
        ),
        _ => null,
      },
    );
  }

  Widget _choose(BuildContext context) {
    final l = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.sellerImportIntro, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        BigTile(
          key: const Key('import-camera'),
          icon: Icons.photo_camera,
          title: l.sellerImportCamera,
          subtitle: l.sellerImportCameraHint,
          onTap: () => _pick(PickSource.camera),
        ),
        const SizedBox(height: 14),
        BigTile(
          key: const Key('import-gallery'),
          icon: Icons.photo_library,
          title: l.sellerImportGallery,
          subtitle: l.sellerImportGalleryHint,
          color: const Color(0xFF1565C0),
          onTap: () => _pick(PickSource.gallery),
        ),
        const SizedBox(height: 14),
        BigTile(
          key: const Key('import-file'),
          icon: Icons.description,
          title: l.sellerImportFile,
          subtitle: l.sellerImportFileHint,
          color: const Color(0xFF6A1B9A),
          onTap: () => _pick(PickSource.file),
        ),
      ],
    );
  }

  Widget _progress(BuildContext context, String text, String? hint) {
    final t = Theme.of(context).textTheme;
    return ListView(
      key: const Key('import-waiting'),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        const Center(child: SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 6))),
        const SizedBox(height: 28),
        Text(text, textAlign: TextAlign.center, style: t.titleLarge),
        if (hint != null) ...[const SizedBox(height: 14), Text(hint, textAlign: TextAlign.center, style: t.bodyLarge)],
      ],
    );
  }
}
