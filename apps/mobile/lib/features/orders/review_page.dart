import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wholesale_core/wholesale_core.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';
import '../../widgets/common.dart';

/// 给批发商评分：5 颗大星星 + 一键点选的标签 + 可以不填的留言
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  int _rating = 0;
  final Set<ReviewTag> _tags = {};
  final _comment = TextEditingController();
  bool _busy = false;
  bool _prefilled = false;

  static const _goodTags = [
    ReviewTag.onTime,
    ReviewTag.goodQuality,
    ReviewTag.wellPacked,
    ReviewTag.goodPrice,
    ReviewTag.friendly,
  ];
  static const _badTags = [ReviewTag.late, ReviewTag.wrongItems, ReviewTag.damaged, ReviewTag.missingItems];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _prefill(OrderDetail d) {
    if (_prefilled) return;
    _prefilled = true;
    final r = d.review;
    if (r != null) {
      _rating = r.rating;
      _tags.addAll(r.tags);
      _comment.text = r.comment ?? '';
    }
  }

  Future<void> _submit() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref
          .read(buyerActionsProvider)
          .submitReview(
            widget.orderId,
            rating: _rating,
            tags: _tags.toList(),
            comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
          );
      if (!mounted) return;
      showMessage(context, l.reviewThanks);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, l.error(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final detail = ref.watch(orderDetailProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: Text(l.reviewTitle)),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(orderDetailProvider(widget.orderId)),
        builder: (d) {
          _prefill(d);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(d.wholesalerName, style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(l.reviewQuestion, style: t.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      key: Key('star-$i'),
                      iconSize: 54,
                      padding: const EdgeInsets.all(2),
                      onPressed: () => setState(() => _rating = i),
                      icon: Icon(
                        i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: const Color(0xFFF5A623),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final tag in [..._goodTags, ..._badTags])
                    FilterChip(
                      label: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(l.reviewTag(tag), style: t.titleMedium),
                      ),
                      selected: _tags.contains(tag),
                      onSelected: (on) => setState(() => on ? _tags.add(tag) : _tags.remove(tag)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _comment,
                minLines: 2,
                maxLines: 5,
                maxLength: 1000,
                style: t.bodyLarge,
                decoration: InputDecoration(hintText: l.reviewCommentHint),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomAction(
        child: BusyButton(
          key: const Key('submit-review'),
          label: l.submitReview,
          busy: _busy,
          onPressed: _rating == 0 ? null : _submit,
        ),
      ),
    );
  }
}
