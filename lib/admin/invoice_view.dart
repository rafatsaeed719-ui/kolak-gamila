import 'package:flutter/material.dart';

import '../core.dart';
import '../ops.dart';
import '../pdf.dart';
import 'customers.dart';
import 'live.dart';
import 'sale_screen.dart';

Future<void> openInvoice(BuildContext context, Entry e) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceView(entryId: e.id)));

/// تحصيل فاتورة: كلي (الباقي كله) أو جزئي (مبلغ تكتبه)
Future<void> collectInvoice(BuildContext context, Entry e, {required bool full}) async {
  final live = Live.I;
  final cid = (e.m['customerId'] ?? '').toString();
  final acc = live.accountOf(cid);
  final rem = e.remaining;
  if (rem <= 0.004) {
    toast(context, 'الفاتورة دي مسددة');
    return;
  }
  final amount = TextEditingController(text: full ? num2(rem).replaceAll(',', '') : '');
  var method = 'cash';
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('${full ? 'تحصيل كلي' : 'تحصيل جزئي'} — ${invoiceLabel(e.invoiceNo)}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('الباقي على الفاتورة: ${money(rem)}'),
          SizedBox(height: 12),
          numField(amount, 'المبلغ', autofocus: !full),
          SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: method,
            decoration: InputDecoration(labelText: 'طريقة الدفع'),
            items: kPayMethods.entries.map((m) => DropdownMenuItem(value: m.key, child: Text(m.value))).toList(),
            onChanged: (v) => setS(() => method = v ?? 'cash'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('تحصيل')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final v = toD(amount.text);
  if (v <= 0) return;
  try {
    await savePayment(
      customerId: cid,
      phone: (e.m['phone'] ?? '').toString(),
      account: acc,
      amount: v,
      chosen: [],
      note: 'تحصيل ${invoiceLabel(e.invoiceNo)}',
      date: DateTime.now(),
      method: method,
      onlySale: e.id,
    );
    if (context.mounted) toast(context, 'اتحصّل ${money(v)}');
  } catch (err) {
    if (context.mounted) toast(context, authError(err), error: true);
  }
}

/// مرتجع: تختار الكميات اللي رجعت من كل صنف
Future<void> returnInvoice(BuildContext context, Entry e) async {
  final items = e.items;
  if (items.isEmpty) {
    toast(context, 'الفاتورة دي ملهاش أصناف ترجع', error: true);
    return;
  }
  final qtys = <int, double>{};
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(builder: (d, setS) {
      var value = 0.0;
      qtys.forEach((i, q) => value += q * toD(items[i]['price']));
      return AlertDialog(
        title: Text('مرتجع من ${invoiceLabel(e.invoiceNo)}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < items.length; i++)
                Builder(builder: (_) {
                  final it = items[i];
                  final can = toD(it['qty']) - toD(it['returned']);
                  final q = qtys[i] ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text((it['name'] ?? '').toString()),
                    subtitle: Text('اتباع ${num2(it['qty'])}${toD(it['returned']) > 0 ? ' · رجع قبل كده ${num2(it['returned'])}' : ''} · ${money(it['price'])}'),
                    trailing: can <= 0
                        ? Text('رجع كله')
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                icon: Icon(Icons.remove_circle_outline),
                                onPressed: q <= 0 ? null : () => setS(() => qtys[i] = q - 1)),
                            Text(num2(q), style: TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                                icon: Icon(Icons.add_circle_outline),
                                onPressed: q >= can ? null : () => setS(() => qtys[i] = q + 1)),
                          ]),
                  );
                }),
              SizedBox(height: 8),
              TextField(controller: note, decoration: InputDecoration(labelText: 'سبب المرتجع (اختياري)')),
              SizedBox(height: 10),
              Text('قيمة المرتجع: ${money(value)}', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('هيتخصم من حساب العميل والبضاعة هترجع للمخزن.', style: TextStyle(fontSize: 12)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
          FilledButton(onPressed: value <= 0 ? null : () => Navigator.pop(d, true), child: Text('سجّل المرتجع')),
        ],
      );
    }),
  );
  if (ok != true) return;
  try {
    await saveReturn(sale: e, qtys: qtys, note: note.text.trim());
    if (context.mounted) toast(context, 'اتسجل المرتجع');
  } catch (err) {
    if (context.mounted) toast(context, authError(err), error: true);
  }
}

class InvoiceView extends StatelessWidget {
  final String entryId;
  const InvoiceView({super.key, required this.entryId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        Entry? e;
        for (final x in live.entries) {
          if (x.id == entryId) e = x;
        }
        if (e == null) {
          return Scaffold(appBar: AppBar(), body: EmptyView('الفاتورة دي مش موجودة', text: 'ممكن تكون اتحذفت.'));
        }
        final inv = e;
        final cid = (inv.m['customerId'] ?? '').toString();
        final cust = live.customer(cid)?.data() ?? {'name': live.customerName(cid), 'code': 0};
        final acc = live.accountOf(cid);
        final returns = acc.entries.where((x) => x.kind == 'return' && x.m['saleId'] == inv.id).toList();
        final pays = acc.entries
            .where((x) => x.kind == 'pay' && x.allocations.any((a) => a['entryId'] == inv.id))
            .toList();
        Widget row(String a, String b, {Color? color, bool bold = false}) => Padding(
              padding: EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Text(a, style: TextStyle(color: kMuted)),
                const Spacer(),
                Text(b, style: TextStyle(color: color, fontWeight: bold ? FontWeight.bold : null)),
              ]),
            );
        return Scaffold(
          appBar: AppBar(title: Text('فاتورة ${invoiceLabel(inv.invoiceNo)}'), actions: [
            IconButton(
              tooltip: 'طباعة / مشاركة PDF',
              icon: Icon(Icons.print_outlined),
              onPressed: () => shareInvoicePdf(context, cust, inv),
            ),
          ]),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 760),
              child: ListView(padding: EdgeInsets.all(12), children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Text(invoiceLabel(inv.invoiceNo),
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        SizedBox(width: 10),
                        invoiceStatusPill(inv.status),
                        const Spacer(),
                        Text(fmtDate(inv.date, time: true), style: TextStyle(color: kMuted)),
                      ]),
                      SizedBox(height: 10),
                      InkWell(
                        onTap: cid == 'cash'
                            ? null
                            : () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => CustomerDetail(customerId: cid))),
                        child: Row(children: [
                          Icon(Icons.person_outline, size: 18),
                          SizedBox(width: 6),
                          Text((cust['name'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w600)),
                          if (cid != 'cash') ...[SizedBox(width: 8), CodeBadge(cust['code'])],
                        ]),
                      ),
                      SizedBox(height: 6),
                      Wrap(spacing: 16, runSpacing: 4, children: [
                        Text('الدفع: ${payMethodLabel(inv.payMethod)}', style: TextStyle(color: kMuted)),
                        if (inv.rep.isNotEmpty) Text('المندوب: ${inv.rep}', style: TextStyle(color: kMuted)),
                        if (inv.by.isNotEmpty) Text('سجّلها: ${inv.by}', style: TextStyle(color: kMuted)),
                      ]),
                    ]),
                  ),
                ),
                SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStatePropertyAll(kBlush),
                      columns: [
                        DataColumn(label: Text('الصنف')),
                        DataColumn(label: Text('الكمية'), numeric: true),
                        DataColumn(label: Text('السعر'), numeric: true),
                        DataColumn(label: Text('الإجمالي'), numeric: true),
                        DataColumn(label: Text('رجع'), numeric: true),
                      ],
                      rows: inv.items
                          .map((it) => DataRow(cells: [
                                DataCell(Text('${it['name']}${(it['code'] ?? '').toString().isEmpty ? '' : '  ${it['code']}'}')),
                                DataCell(Text(num2(it['qty']))),
                                DataCell(Text(num2(it['price']))),
                                DataCell(Text(num2(toD(it['qty']) * toD(it['price'])))),
                                DataCell(Text(toD(it['returned']) > 0 ? num2(it['returned']) : '—')),
                              ]))
                          .toList(),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(children: [
                      row('الإجمالي', money(inv.gross)),
                      if (inv.discount > 0) row('الخصم', '- ${money(inv.discount)}', color: kOwe),
                      row('الصافي', money(inv.debit), bold: true),
                      row('اتدفع مع الفاتورة', money(inv.credit), color: kPaid),
                      for (final p in pays)
                        row('تحصيل ${fmtDate(p.date)} (${payMethodLabel(p.m['method'])})',
                            money(p.allocations.where((a) => a['entryId'] == inv.id).fold(0.0, (s, a) => s + toD(a['amount']))),
                            color: kPaid),
                      for (final r in returns) row('مرتجع ${fmtDate(r.date)}', money(r.credit), color: kMuted),
                      const Divider(),
                      row('الباقي على الفاتورة', money(inv.remaining),
                          bold: true, color: inv.remaining > 0.004 ? kOwe : kPaid),
                      if (inv.note.isNotEmpty) ...[Divider(), Align(alignment: AlignmentDirectional.centerStart, child: Text(inv.note))],
                    ]),
                  ),
                ),
                if (inv.photos.isNotEmpty) ...[
                  SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in inv.photos)
                      InkWell(
                        onTap: () => showPhoto(context, p),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(10), child: B64Image(p, width: 90, height: 90)),
                      ),
                  ]),
                ],
                SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (Me.can('sell') && inv.remaining > 0.004) ...[
                    FilledButton.icon(
                        onPressed: () => collectInvoice(context, inv, full: true),
                        icon: Icon(Icons.done_all, size: 18),
                        label: Text('تحصيل كلي')),
                    OutlinedButton.icon(
                        onPressed: () => collectInvoice(context, inv, full: false),
                        icon: Icon(Icons.payments_outlined, size: 18),
                        label: Text('تحصيل جزئي')),
                  ],
                  OutlinedButton.icon(
                      onPressed: () => shareInvoicePdf(context, cust, inv),
                      icon: Icon(Icons.print_outlined, size: 18),
                      label: Text('طباعة / PDF')),
                  if ((cust['phone'] ?? '').toString().isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => openWhatsApp(
                          cust['phone'].toString(),
                          'أهلاً ${cust['name']} 🌸\nفاتورتك ${invoiceLabel(inv.invoiceNo)} من «${Brand.name}» بتاريخ ${fmtDate(inv.date)}:\n'
                          '${inv.items.map((it) => '• ${it['name']} × ${num2(it['qty'])} = ${num2(toD(it['qty']) * toD(it['price']))}').join('\n')}\n'
                          '${inv.discount > 0 ? 'الخصم: ${money(inv.discount)}\n' : ''}'
                          'الصافي: ${money(inv.debit)}\nالباقي عليها: ${money(inv.remaining)}\n'
                          'إجمالي حسابك: ${money(acc.balance)}'),
                      icon: Icon(Icons.chat_outlined, size: 18),
                      label: Text('واتساب'),
                    ),
                  if (Me.can('sell') && inv.status != 'returned')
                    OutlinedButton.icon(
                        onPressed: () => returnInvoice(context, inv),
                        icon: Icon(Icons.undo, size: 18),
                        label: Text('مرتجع')),
                  if (Me.can('edit'))
                    OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => SaleScreen(customerId: cid, old: inv))),
                        icon: Icon(Icons.edit_outlined, size: 18),
                        label: Text('تعديل')),
                  if (Me.can('edit'))
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: kOwe),
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        if (!await confirm(context, 'حذف الفاتورة؟', 'المبلغ هيتشال من حساب العميل والبضاعة هترجع للمخزن.',
                            ok: 'احذف', danger: true)) {
                          return;
                        }
                        await deleteEntry(inv, acc);
                        nav.pop();
                      },
                      icon: Icon(Icons.delete_outline, size: 18),
                      label: Text('حذف'),
                    ),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}
