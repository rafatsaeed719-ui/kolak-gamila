import 'package:flutter/material.dart';

import '../core.dart';
import '../ops.dart';
import 'customers.dart';
import 'live.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String filter = 'open';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final list = Live.I.orders.where((o) {
          final s = o.data()['status'];
          if (filter == 'open') return s == 'new' || s == 'ready';
          if (filter == 'done') return s == 'delivered';
          return s == 'cancelled';
        }).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('طلبات العملاء')),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'open', label: Text('مفتوحة')),
                  ButtonSegment(value: 'done', label: Text('اتسلّمت')),
                  ButtonSegment(value: 'cancelled', label: Text('ملغية')),
                ],
                selected: {filter},
                onSelectionChanged: (s) => setState(() => filter = s.first),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyView('مفيش طلبات هنا',
                      text: 'العملاء بيطلبوا من المعرض والعروض في التطبيق.', icon: Icons.shopping_bag_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: list.length,
                      itemBuilder: (_, i) => OrderCard(list[i]),
                    ),
            ),
          ]),
        );
      },
    );
  }
}

class OrderCard extends StatelessWidget {
  final Doc o;
  const OrderCard(this.o, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = o.data();
    final items = ((m['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final status = (m['status'] ?? 'new').toString();
    final phone = (m['phone'] ?? '').toString();
    final cust = Live.I.customerForPhone(phone);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text((m['name'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            orderStatusPill(status),
          ]),
          Row(children: [
            Text(phone, textDirection: TextDirection.ltr, style: const TextStyle(color: kMuted)),
            const SizedBox(width: 8),
            if (cust != null) CodeBadge(cust.data()['code']) else const Pill('مش في الدفتر لسه', kMuted),
            const Spacer(),
            Text(fmtDate(m['createdAt'], time: true), style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
          const Divider(),
          ...items.map((it) => Row(children: [
                Expanded(child: Text('${it['name']}  ×${num2(it['qty'])}')),
                Text(num2(toD(it['qty']) * toD(it['price']))),
              ])),
          const Divider(),
          Row(children: [
            const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(money(m['total']), style: const TextStyle(fontWeight: FontWeight.bold, color: kPlum)),
          ]),
          if ((m['note'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('ملاحظة: ${m['note']}'),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (status == 'new')
              OutlinedButton(
                onPressed: () async {
                  await db.collection('orders').doc(o.id).update({'status': 'ready'});
                },
                child: const Text('جاهز للاستلام'),
              ),
            if (status == 'new' || status == 'ready')
              FilledButton.icon(
                onPressed: () => _deliver(context, m),
                icon: const Icon(Icons.check),
                label: const Text('اتسلّم — سجّله على حسابه'),
              ),
            if (status == 'new' || status == 'ready')
              TextButton(
                style: TextButton.styleFrom(foregroundColor: kOwe),
                onPressed: () async {
                  if (await confirm(context, 'إلغاء الطلب؟', 'العميل هيشوف إن الطلب اتلغى.',
                      ok: 'إلغاء الطلب', danger: true)) {
                    await db.collection('orders').doc(o.id).update({'status': 'cancelled'});
                  }
                },
                child: const Text('إلغاء'),
              ),
            if (phone.isNotEmpty)
              TextButton.icon(
                onPressed: () => openWhatsApp(phone,
                    'أهلاً ${m['name'] ?? ''} 🌸 طلبك من «$kStoreName» بقيمة ${money(m['total'])} ${status == 'ready' ? 'جاهز للاستلام' : 'وصلنا'}.'),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('واتساب'),
              ),
            if (status == 'delivered' && m['customerId'] != null)
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CustomerDetail(customerId: m['customerId']))),
                child: const Text('افتح حسابه'),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _deliver(BuildContext context, Map<String, dynamic> m) async {
    final paid = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تسليم الطلب'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('هيتسجل بيع بـ ${money(m['total'])} على حساب ${m['name']}، والبضاعة هتتخصم من المخزن.'),
          const SizedBox(height: 12),
          numField(paid, 'دفع كام وهو بيستلم؟ (اختياري)'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('سجّل')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await deliverOrder(o.id, m, paid: toD(paid.text));
      if (context.mounted) toast(context, 'اتسجل على حسابه');
    } catch (e) {
      if (context.mounted) toast(context, authError(e), error: true);
    }
  }
}
