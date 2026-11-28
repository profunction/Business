import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n_x.dart';
import '../../app/providers.dart';

/// 右上角的购物车（带数量）
class CartButton extends ConsumerWidget {
  const CartButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartQuoteProvider).value?.lineCount ?? 0;
    return IconButton(
      key: const Key('cart-button'),
      tooltip: context.l10n.cartTitle,
      // 购物车是底部导航的分页：用 go（不是 push）
      onPressed: () => context.go('/cart'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.shopping_cart_outlined),
      ),
    );
  }
}
