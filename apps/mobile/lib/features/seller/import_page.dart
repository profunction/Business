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

/// 上传之前先检查（太大 / HEIC / 看不懂的格式），回传要上传的内容。不对就丢 AppError（l.error 有三语说明）
Future<({Uint8List bytes, FileKind kind})> readPriceListFile(PickedFile file) async {
  // 知道大小的话，太大的不用读进来
  if ((file.size ?? 0) > priceListMaxBytes) throw const AppError('FILE_TOO_LARGE');
  final bytes = await file.readAsBytes();
  final kind = checkPriceListFile(bytes, fileName: file.name);
  return (bytes: bytes, kind: kind);
}

enum _Stage { choose, uploading, waiting, failed }

/// 上传价目表：三个大按钮「拍照」「选照片」「选文件（Excel、PDF）」→ 上传 → 等 AI（每 3 秒查一次，最多 5 分钟）
/// → 读好了去确认页；读不到就说原因，可以再上传一次。[importId] 有给的话直接等那一份（从首页回来看）
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.importId});

  final String? importId;

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

  @override
  void initState() {
    super.initState();
    final id = widget.importId;
    if (id != null && isUuid(id)) _wait(id);
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
          : await device.pickImage(source, maxWidth: 2576, imageQuality: 85);
      if (file == null || !mounted) return;
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
                _fail(context.l10n.importFailure(imp.errorMessage));
              case ImportStatus.applied:
                context.pushReplacement('/seller/import/${imp.id}');
            }
          },
          onError: (Object e) {
            if (mounted) _fail(context.l10n.error(e));
          },
        );
  }

  void _fail(String reason) => setState(() {
    _stage = _Stage.failed;
    _failure = reason;
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
        _Stage.failed => CenterMessage(
          key: const Key('import-failed'),
          icon: Icons.error_outline,
          iconColor: AppTheme.problem,
          text: l.sellerImportFailedTitle,
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
        // 等的时候可以先回首页做别的事（读好了首页会显示）
        _Stage.waiting => BottomAction(
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
