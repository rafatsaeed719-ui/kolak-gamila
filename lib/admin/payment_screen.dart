import 'package:flutter/material.dart';

import '../core.dart';
import '../ops.dart';
import 'live.dart';

/// تسجيل دفعة، مع اختيار الأصناف اللي العميل دافع تمنها
class PaymentScreen extends StatefulWidget {
  final String customerId;
  const PaymentScreen({super.key, required this.customerId});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final amount = TextEditingController();
  final note = TextEditingController();
  final chosen = <String>[]; // saleId:idx بالترتيب
  bool typed = false;
  bool busy = false;
  DateTime date = DateTime.now();

  String _key(OpenItem o) => '${o.sale.id}:${o.index}';

  @override
  Widget build(BuildContext context) {
    final c = Live.I.customer(widget.customerId);
    final acc = Live.I.accountOf(widget.customerId);
    final open = acc.openItems;
    final byKey = {for (final o in open) _key(o): o};
    final selected = chosen.where(byKey.containsKey).map((k) => byKey[k]!).toList();
    final selTotal = selected.fold(0.0, (a, o) => a + o.remaining);
    final amt = toD(amount.text);

    return Scaffold(
      appBar: AppBar(title: Text('دفعة — ${c?.data()['name'] ?? ''}')),
      body: ListView(padding: const EdgeInsets.only(bottom: 110), children: [
        Card(
          child: ListTile(
            title: const Text('عليه دلوقتي'),
            trailing: Text(money(acc.balance),
                style: const TextStyle(fontWeight: FontWeight.bold, color: kOwe, fontSize: 17)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(children: [
            numField(amount, 'دفع كام؟', autofocus: true, onChanged: (_) => setState(() => typed = true)),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('التاريخ: ${fmtDate(date)}'),
              trailing: TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => date = d);
                },
                child: const Text('تغيير'),
              ),
            ),
          ]),
        ),
        SectionTitle('دفع تمن إيه؟ (اختياري)',
            trailing: selected.isEmpty
                ? null
                : TextButton(
                    onPressed: () => setState(() {
                      chosen.clear();
                      if (!typed) amount.clear();
                    }),
                    child: const Text('مسح الاختيار'))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('علّم على الأصناف اللي دفع تمنها. لو مااخترتش حاجة، الدفعة بتتحسب على الأقدم.',
              style: TextStyle(color: kMuted, fontSize: 13)),
        ),
        const SizedBox(height: 6),
        if (open.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('مفيش أصناف عليها فلوس.', style: TextStyle(color: kMuted)),
          ),
        ...open.map((o) {
          final k = _key(o);
          final on = chosen.contains(k);
          return Card(
            child: CheckboxListTile(
              value: on,
              onChanged: (v) => setState(() {
                if (v == true) {
                  chosen.add(k);
                } else {
                  chosen.remove(k);
                }
                if (!typed) {
                  final t = chosen
                      .where(byKey.containsKey)
                      .fold(0.0, (a, x) => a + byKey[x]!.remaining);
                  amount.text = t > 0 ? num2(t).replaceAll(',', '') : '';
                }
              }),
              title: Text('${o.item['name']}  ×${num2(o.item['qty'])}'),
              subtitle: Text(
                  '${fmtDate(o.sale.date)}${o.sale.invoiceNo > 0 ? ' · فاتورة #${o.sale.invoiceNo}' : ''}'
                  '${o.remaining < o.total ? ' · اتدفع منه ${num2(o.total - o.remaining)}' : ''}'),
              secondary: Text(num2(o.remaining),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: kOwe)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          );
        }),
      ]),
      bottomSheet: Material(
        elevation: 8,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (selected.isNotEmpty)
                    Text('الأصناف المختارة: ${money(selTotal)}',
                        style: const TextStyle(fontSize: 12, color: kMuted)),
                  Text('هيبقى عليه ${money(acc.balance - amt)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: acc.balance - amt > 0 ? kOwe : kPaid)),
                ]),
              ),
              FilledButton(
                onPressed: busy || c == null
                    ? null
                    : () async {
                        if (amt <= 0) {
                          toast(context, 'اكتب المبلغ اللي دفعه', error: true);
                          return;
                        }
                        setState(() => busy = true);
                        try {
                          await savePayment(
                            customerId: c.id,
                            phone: (c.data()['phone'] ?? '').toString(),
                            account: acc,
                            amount: amt,
                            chosen: selected,
                            note: note.text.trim(),
                            date: date,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          toast(context, 'اتسجلت الدفعة ${money(amt)}');
                        } catch (e) {
                          if (context.mounted) toast(context, authError(e), error: true);
                          if (mounted) setState(() => busy = false);
                        }
                      },
                style: FilledButton.styleFrom(
                    backgroundColor: kPaid, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                child: const Text('حفظ الدفعة'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
