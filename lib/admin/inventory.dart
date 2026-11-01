import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core.dart';
import '../ops.dart';
import 'live.dart';
import 'money_screens.dart';
import 'products.dart';
import 'shell.dart';

/// المخزون الحرج: الأصناف اللي قربت تخلص
class LowStockScreen extends StatelessWidget {
  const LowStockScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        final list = live.lowStock
          ..sort((a, b) => toD(a.data()['stock']).compareTo(toD(b.data()['stock'])));
        final out = list.where((p) => toD(p.data()['stock']) <= 0).length;
        return Scaffold(
          appBar: pageAppBar(context, 'المخزون الحرج'),
          body: ListView(padding: EdgeInsets.only(bottom: 30, top: 8), children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(child: StatBox('أصناف قربت تخلص', '${list.length - out}', color: kWarn, icon: Icons.warning_amber_rounded)),
                SizedBox(width: 8),
                Expanded(child: StatBox('أصناف خلصت', '$out', color: kOwe, icon: Icons.remove_shopping_cart_outlined)),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text('الصنف بيظهر هنا لما كميته توصل للحد اللي محدده في «نبّهني لما توصل».',
                  style: TextStyle(color: kMuted, fontSize: 12.5)),
            ),
            if (list.isEmpty) EmptyView('كل الأصناف كمياتها كويسة 👌', icon: Icons.inventory_2_outlined),
            ...list.map((p) {
              final m = p.data();
              final s = toD(m['stock']);
              return Card(
                child: ListTile(
                  leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: B64Image(m['image']?.toString(), width: 48, height: 48)),
                  title: Text((m['name'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${m['code'] ?? ''} · الحد ${num2(m['minStock'] ?? 2)}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Pill(s <= 0 ? 'خلص' : '${num2(s)} متاح', s <= 0 ? kOwe : kWarn),
                    if (Me.can('purchases'))
                      IconButton(
                        tooltip: 'اشتري',
                        icon: Icon(Icons.add_shopping_cart),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseForm())),
                      ),
                  ]),
                  onTap: Me.can('products')
                      ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(p: p)))
                      : null,
                ),
              );
            }),
          ]),
        );
      },
    );
  }
}

/// الهالك: البضاعة اللي اتكسرت أو باظت أو انتهت صلاحيتها
class DamagedScreen extends StatelessWidget {
  const DamagedScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final live = Live.I;
    Doc? product;
    final qty = TextEditingController(text: '1');
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('تسجيل هالك'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: product?.id,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'الصنف'),
                items: live.products
                    .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.data()['name']}${p.data()['stock'] != null ? ' (متاح ${num2(p.data()['stock'])})' : ''}',
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setS(() => product = live.product(v ?? '')),
              ),
              SizedBox(height: 10),
              numField(qty, 'الكمية'),
              SizedBox(height: 10),
              TextField(
                  controller: reason,
                  decoration: InputDecoration(labelText: 'السبب', hintText: 'اتكسر، باظ، انتهت صلاحيته…')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('سجّل')),
          ],
        ),
      ),
    );
    if (ok != true || product == null || toD(qty.text) <= 0) return;
    try {
      await saveDamaged(
        productId: product!.id,
        name: (product!.data()['name'] ?? '').toString(),
        qty: toD(qty.text),
        cost: live.costOf(product!.id) > 0 ? live.costOf(product!.id) : toD(product!.data()['price']),
        reason: reason.text.trim(),
      );
      if (context.mounted) toast(context, 'اتسجل الهالك واتخصم من المخزن');
    } catch (e) {
      if (context.mounted) toast(context, authError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final list = Live.I.damaged;
        final now = DateTime.now();
        final month = list.where((x) {
          final d = tsToDate(x.data()['date']);
          return d != null && d.year == now.year && d.month == now.month;
        }).fold(0.0, (a, x) => a + toD(x.data()['value']));
        return Scaffold(
          appBar: pageAppBar(context, 'هالك'),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => _add(context),
            icon: Icon(Icons.add),
            label: Text('تسجيل هالك'),
          ),
          body: ListView(padding: EdgeInsets.only(bottom: 90, top: 8), children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: StatBox('قيمة الهالك الشهر ده', money(month), color: kOwe, icon: Icons.broken_image_outlined),
            ),
            if (list.isEmpty)
              EmptyView('مفيش هالك', text: 'سجّل أي بضاعة اتكسرت أو باظت، وهتتخصم من المخزن.', icon: Icons.broken_image_outlined),
            ...list.map((x) {
              final m = x.data();
              return Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: kBlush, child: Icon(Icons.broken_image_outlined, color: kOwe)),
                  title: Text('${m['name']} × ${num2(m['qty'])}'),
                  subtitle: Text('${fmtDate(m['date'])}${(m['reason'] ?? '').toString().isEmpty ? '' : ' · ${m['reason']}'}'
                      '${(m['by'] ?? '').toString().isEmpty ? '' : ' · ${m['by']}'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(m['value']), style: TextStyle(color: kOwe, fontWeight: FontWeight.bold)),
                    if (Me.can('edit'))
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          if (await confirm(context, 'حذف؟', 'الكمية هترجع للمخزن.', ok: 'احذف', danger: true)) {
                            await deleteDamaged(x.id, m);
                          }
                        },
                      ),
                  ]),
                ),
              );
            }),
          ]),
        );
      },
    );
  }
}

/// للاستخدام في أماكن تانية
Timestamp nowTs() => Timestamp.now();
