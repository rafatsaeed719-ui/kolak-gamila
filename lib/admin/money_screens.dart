import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core.dart';
import '../ops.dart';
import '../pdf.dart';
import 'customers.dart';
import 'live.dart';
import 'payment_screen.dart';
import 'shell.dart';

// ======================== اختيار عميل ========================

Future<Doc?> pickCustomer(BuildContext context, {bool includeCash = false}) {
  return showDialog<Doc>(context: context, builder: (_) => _PickCustomer(includeCash: includeCash));
}

class _PickCustomer extends StatefulWidget {
  final bool includeCash;
  const _PickCustomer({required this.includeCash});
  @override
  State<_PickCustomer> createState() => _PickCustomerState();
}

class _PickCustomerState extends State<_PickCustomer> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final live = Live.I;
    final query = q.trim().toLowerCase().replaceAll('#', '');
    final list = live.customers.where((c) {
      if (c.id == kCashId && !widget.includeCash) return false;
      final m = c.data();
      return query.isEmpty ||
          (m['name'] ?? '').toString().toLowerCase().contains(query) ||
          pad4(m['code']).contains(query) ||
          (m['phone'] ?? '').toString().contains(query);
    }).toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(hintText: 'اسم العميل أو الكود أو الرقم', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Flexible(
            child: list.isEmpty
                ? Padding(padding: EdgeInsets.all(24), child: Text('مفيش عميل بالاسم ده'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final b = live.accountOf(c.id).balance;
                      return ListTile(
                        leading: CodeBadge(c.data()['code']),
                        title: Text((c.data()['name'] ?? '').toString()),
                        trailing: b > 0.004 ? Text(money(b), style: TextStyle(color: kOwe)) : null,
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

Future<void> pickCustomerThenPay(BuildContext context) async {
  final c = await pickCustomer(context);
  if (c == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(customerId: c.id)));
}

// ======================== العملاء والموردين ========================

class PartiesScreen extends StatelessWidget {
  const PartiesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!Me.can('purchases')) return CustomersScreen();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: pageAppBar(context, 'العملاء والموردين',
            bottom: TabBar(tabs: [Tab(text: 'العملاء'), Tab(text: 'الموردين')])),
        body: TabBarView(children: [CustomersScreen(bare: true), SuppliersBody()]),
      ),
    );
  }
}

class SuppliersBody extends StatefulWidget {
  const SuppliersBody({super.key});
  @override
  State<SuppliersBody> createState() => _SuppliersBodyState();
}

class _SuppliersBodyState extends State<SuppliersBody> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        final query = q.trim().toLowerCase();
        final list = live.suppliers
            .where((s) => query.isEmpty || (s.data()['name'] ?? '').toString().toLowerCase().contains(query))
            .toList();
        final total = live.suppliers.fold(0.0, (a, s) => a + live.supplierBalance(s.id));
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
           heroTag: null,
            heroTag: null,
            onPressed: () => supplierForm(context),
            icon: Icon(Icons.add_business_outlined),
            label: Text('مورد جديد'),
          ),
          body: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                decoration: InputDecoration(hintText: 'ابحث باسم المورد', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Text('${list.length} مورد', style: TextStyle(color: kMuted)),
                const Spacer(),
                Text('عليك للموردين ${money(total)}', style: TextStyle(color: kOwe, fontWeight: FontWeight.bold)),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? EmptyView('مفيش موردين', text: 'ضيف الموردين اللي بتشتري منهم.', icon: Icons.store_outlined)
                  : ListView(
                      padding: EdgeInsets.only(bottom: 90),
                      children: list.map((s) {
                        final b = live.supplierBalance(s.id);
                        return Card(
                          child: ListTile(
                            leading: CodeBadge(s.data()['code']),
                            title: Text((s.data()['name'] ?? '').toString()),
                            subtitle: Text((s.data()['phone'] ?? '').toString()),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(num2(b.abs()),
                                    style: TextStyle(fontWeight: FontWeight.bold, color: b > 0 ? kOwe : kPaid)),
                                Text(b > 0.004 ? 'ليه عندك' : 'خالص', style: TextStyle(fontSize: 11, color: kMuted)),
                              ],
                            ),
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => SupplierDetail(supplierId: s.id))),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ]),
        );
      },
    );
  }
}

Future<void> supplierForm(BuildContext context, {Doc? s}) async {
  final m = s?.data() ?? {};
  final name = TextEditingController(text: (m['name'] ?? '').toString());
  final phone = TextEditingController(text: (m['phone'] ?? '').toString());
  final notes = TextEditingController(text: (m['notes'] ?? '').toString());
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(s == null ? 'مورد جديد' : 'تعديل المورد'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: 'الاسم')),
        SizedBox(height: 10),
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'الموبايل')),
        SizedBox(height: 10),
        TextField(controller: notes, decoration: InputDecoration(labelText: 'ملاحظات')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('حفظ')),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return;
  final data = {'name': name.text.trim(), 'phone': normPhone(phone.text), 'notes': notes.text.trim()};
  if (s == null) {
    final code = Live.I.suppliers.fold(0, (a, x) => toI(x.data()['code']) > a ? toI(x.data()['code']) : a) + 1;
    await db.collection('suppliers').add({...data, 'code': code, 'createdAt': FieldValue.serverTimestamp()});
  } else {
    await db.collection('suppliers').doc(s.id).update(data);
  }
}

class SupplierDetail extends StatelessWidget {
  final String supplierId;
  const SupplierDetail({super.key, required this.supplierId});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        final s = live.supplier(supplierId);
        if (s == null) return Scaffold(appBar: AppBar(), body: EmptyView('المورد ده مش موجود'));
        final m = s.data();
        final moves = <MapEntry<DateTime, Widget>>[];
        for (final p in live.purchases.where((p) => p.data()['supplierId'] == supplierId)) {
          final pm = p.data();
          moves.add(MapEntry(
            tsToDate(pm['date']) ?? DateTime(2000),
            Card(
              child: ListTile(
                leading: Pill(purchaseLabel(toI(pm['no'])), kInk),
                title: Text('فاتورة شرا ${money(pm['total'])}'),
                subtitle: Text('${fmtDate(pm['date'])} · دفعت ${money(pm['paid'])}'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseForm(doc: p))),
              ),
            ),
          ));
        }
        for (final v in live.vouchers.where((v) => v.data()['partyId'] == supplierId)) {
          final vm = v.data();
          moves.add(MapEntry(
            tsToDate(vm['date']) ?? DateTime(2000),
            Card(
              child: ListTile(
                leading: Pill(voucherLabel('out', toI(vm['no'])), kPaid),
                title: Text('سند صرف ${money(vm['amount'])}'),
                subtitle: Text('${fmtDate(vm['date'])} · ${payMethodLabel(vm['method'])}'),
              ),
            ),
          ));
        }
        moves.sort((a, b) => b.key.compareTo(a.key));
        final b = live.supplierBalance(supplierId);
        return Scaffold(
          appBar: AppBar(title: Text((m['name'] ?? '').toString()), actions: [
            IconButton(icon: Icon(Icons.edit_outlined), onPressed: () => supplierForm(context, s: s)),
          ]),
          body: ListView(padding: EdgeInsets.only(bottom: 30), children: [
            Card(
              child: ListTile(
                title: Text(b > 0.004 ? 'ليه عندك' : 'الحساب خالص'),
                subtitle: Text((m['phone'] ?? '').toString()),
                trailing: Text(money(b.abs()),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: b > 0 ? kOwe : kPaid)),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => PurchaseForm(supplierId: supplierId))),
                  icon: Icon(Icons.add_shopping_cart, size: 18),
                  label: Text('فاتورة شرا'),
                ),
                OutlinedButton.icon(
                  onPressed: () => voucherForm(context, supplier: s),
                  icon: Icon(Icons.payments_outlined, size: 18),
                  label: Text('ادفعله (سند صرف)'),
                ),
              ]),
            ),
            SectionTitle('الحركات (${moves.length})'),
            ...moves.map((e) => e.value),
          ]),
        );
      },
    );
  }
}

// ======================== المشتريات ========================

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        final list = live.purchases;
        final now = DateTime.now();
        final month = list.where((p) {
          final d = tsToDate(p.data()['date']);
          return d != null && d.year == now.year && d.month == now.month;
        }).fold(0.0, (a, p) => a + toD(p.data()['total']));
        return Scaffold(
          appBar: pageAppBar(context, 'المشتريات'),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseForm())),
            icon: Icon(Icons.add),
            label: Text('فاتورة شرا'),
          ),
          body: ListView(padding: EdgeInsets.only(bottom: 90, top: 8), children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(child: StatBox('مشتريات الشهر', money(month), icon: Icons.shopping_cart_outlined)),
                SizedBox(width: 8),
                Expanded(
                  child: StatBox(
                      'عليك للموردين',
                      money(live.suppliers.fold(0.0, (a, s) => a + live.supplierBalance(s.id))),
                      color: kOwe,
                      icon: Icons.store_outlined),
                ),
              ]),
            ),
            SizedBox(height: 6),
            if (list.isEmpty)
              EmptyView('مفيش مشتريات',
                  text: 'سجّل البضاعة اللي بتشتريها، والكمية هتتزود في المخزن لوحدها.', icon: Icons.shopping_cart_outlined),
            ...list.map((p) {
              final m = p.data();
              final rem = toD(m['total']) - toD(m['paid']);
              return Card(
                child: ListTile(
                  leading: Pill(purchaseLabel(toI(m['no'])), kInk),
                  title: Text((m['supplierName'] ?? '').toString().isEmpty ? 'بدون مورد' : m['supplierName'].toString()),
                  subtitle: Text('${fmtDate(m['date'])} · ${((m['items'] as List?) ?? []).length} صنف'
                      '${rem > 0.004 ? ' · باقي ${money(rem)}' : ''}'),
                  trailing: Text(money(m['total']), style: TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseForm(doc: p))),
                ),
              );
            }),
          ]),
        );
      },
    );
  }
}

class PurchaseForm extends StatefulWidget {
  final Doc? doc;
  final String? supplierId;
  const PurchaseForm({super.key, this.doc, this.supplierId});
  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  late final Map<String, dynamic> m = widget.doc?.data() ?? {};
  late String supplierId = (m['supplierId'] ?? widget.supplierId ?? '').toString();
  late final List<PurchaseLine> lines = ((m['items'] as List?) ?? [])
      .map((e) => PurchaseLine.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
  late final discount = TextEditingController(text: toD(m['discount']) > 0 ? num2(m['discount']).replaceAll(',', '') : '');
  late final paid = TextEditingController(text: toD(m['paid']) > 0 ? num2(m['paid']).replaceAll(',', '') : '');
  late final note = TextEditingController(text: (m['note'] ?? '').toString());
  late String method = (m['method'] ?? 'cash').toString();
  late DateTime date = tsToDate(m['date']) ?? DateTime.now();
  bool busy = false;

  double get gross => lines.fold(0.0, (a, l) => a + l.total);

  Future<void> _addProduct() async {
    final live = Live.I;
    final p = await showDialog<Doc>(
      context: context,
      builder: (d) {
        var q = '';
        return StatefulBuilder(builder: (d, setS) {
          final list = live.products
              .where((p) => q.isEmpty ||
                  (p.data()['name'] ?? '').toString().contains(q) ||
                  (p.data()['code'] ?? '').toString().contains(q))
              .toList();
          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 480, maxHeight: 520),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: EdgeInsets.all(12),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(hintText: 'اسم الصنف أو الكود', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setS(() => q = v.trim()),
                  ),
                ),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final p in list)
                      ListTile(
                        leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: B64Image(p.data()['image']?.toString(), width: 40, height: 40)),
                        title: Text((p.data()['name'] ?? '').toString()),
                        subtitle: Text('${p.data()['code'] ?? ''} · متاح ${num2(p.data()['stock'] ?? 0)}'),
                        onTap: () => Navigator.pop(d, p),
                      ),
                  ]),
                ),
              ]),
            ),
          );
        });
      },
    );
    if (p == null) return;
    setState(() => lines.add(PurchaseLine(
        productId: p.id, name: (p.data()['name'] ?? '').toString(), cost: live.costOf(p.id), qty: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final live = Live.I;
    final total = gross - toD(discount.text);
    return Scaffold(
      appBar: AppBar(title: Text(widget.doc == null ? 'فاتورة شرا جديدة' : 'فاتورة ${purchaseLabel(toI(m['no']))}')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 760),
          child: ListView(padding: EdgeInsets.all(14), children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: live.suppliers.any((s) => s.id == supplierId) ? supplierId : '',
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'المورد'),
                  items: [
                    DropdownMenuItem(value: '', child: Text('بدون مورد')),
                    ...live.suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text((s.data()['name'] ?? '').toString()))),
                  ],
                  onChanged: (v) => setState(() => supplierId = v ?? ''),
                ),
              ),
              IconButton(tooltip: 'مورد جديد', onPressed: () => supplierForm(context), icon: Icon(Icons.add_business_outlined)),
            ]),
            SectionTitle('الأصناف',
                trailing: TextButton.icon(onPressed: _addProduct, icon: Icon(Icons.add), label: Text('صنف'))),
            if (lines.isEmpty)
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('اختار الأصناف اللي اشتريتها. الكمية هتتزود في المخزن، وسعر الشرا هيتحدث.',
                    style: TextStyle(color: kMuted)),
              ),
            for (var i = 0; i < lines.length; i++)
              Card(
                margin: EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(lines[i].name, style: TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: num2(lines[i].qty).replaceAll(',', ''),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'الكمية'),
                        onChanged: (v) => setState(() => lines[i].qty = toD(v)),
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: num2(lines[i].cost).replaceAll(',', ''),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'سعر الشرا'),
                        onChanged: (v) => setState(() => lines[i].cost = toD(v)),
                      ),
                    ),
                    SizedBox(width: 70, child: Text(num2(lines[i].total), textAlign: TextAlign.left)),
                    IconButton(
                        icon: Icon(Icons.close, color: kOwe), onPressed: () => setState(() => lines.removeAt(i))),
                  ]),
                ),
              ),
            SizedBox(height: 8),
            Row(children: [
              Expanded(child: numField(discount, 'خصم', onChanged: (_) => setState(() {}))),
              SizedBox(width: 8),
              Expanded(child: numField(paid, 'دفعت كام', onChanged: (_) => setState(() {}))),
            ]),
            SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: method,
              decoration: InputDecoration(labelText: 'طريقة الدفع'),
              items: kPayMethods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => method = v ?? 'cash'),
            ),
            SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: 'ملاحظات')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event),
              title: Text('التاريخ: ${fmtDate(date)}'),
              trailing: TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => date = d);
                },
                child: Text('تغيير'),
              ),
            ),
            Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(children: [
                  Row(children: [Text('الإجمالي'), Spacer(), Text(money(gross))]),
                  Row(children: [
                    Text('الصافي', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(money(total), style: TextStyle(fontWeight: FontWeight.bold))
                  ]),
                  Row(children: [
                    Text('الباقي للمورد'),
                    const Spacer(),
                    Text(money(total - toD(paid.text)), style: TextStyle(color: kOwe))
                  ]),
                ]),
              ),
            ),
            SizedBox(height: 12),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (lines.isEmpty) {
                        toast(context, 'ضيف صنف واحد على الأقل', error: true);
                        return;
                      }
                      setState(() => busy = true);
                      final nav = Navigator.of(context);
                      try {
                        await savePurchase(
                          supplierId: supplierId,
                          supplierName: (live.supplier(supplierId)?.data()['name'] ?? '').toString(),
                          lines: lines,
                          discount: toD(discount.text),
                          paid: toD(paid.text),
                          method: method,
                          note: note.text.trim(),
                          date: date,
                          oldId: widget.doc?.id,
                          old: widget.doc?.data(),
                        );
                        nav.pop();
                      } catch (e) {
                        if (context.mounted) toast(context, authError(e), error: true);
                        if (mounted) setState(() => busy = false);
                      }
                    },
              style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
              child: Text('حفظ فاتورة الشرا'),
            ),
            if (widget.doc != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: kOwe),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (!await confirm(context, 'حذف فاتورة الشرا؟', 'الكميات هتتشال من المخزن.', ok: 'احذف', danger: true)) {
                    return;
                  }
                  await deletePurchase(widget.doc!.id, m);
                  nav.pop();
                },
                icon: Icon(Icons.delete_outline),
                label: Text('حذف'),
              ),
          ]),
        ),
      ),
    );
  }
}

// ======================== سندات التحصيل والصرف ========================

Future<void> voucherForm(BuildContext context, {Doc? supplier}) async {
  final live = Live.I;
  var partyType = supplier != null ? 'supplier' : (live.suppliers.isEmpty ? 'other' : 'supplier');
  var partyId = supplier?.id ?? '';
  final other = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  var method = 'cash';
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('سند صرف'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'supplier', label: Text('لمورد')),
                ButtonSegment(value: 'other', label: Text('جهة تانية')),
              ],
              selected: {partyType},
              onSelectionChanged: (s) => setS(() => partyType = s.first),
            ),
            SizedBox(height: 10),
            if (partyType == 'supplier')
              DropdownButtonFormField<String>(
                value: live.suppliers.any((s) => s.id == partyId) ? partyId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'المورد'),
                items: live.suppliers
                    .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.data()['name']} (ليه ${num2(live.supplierBalance(s.id))})')))
                    .toList(),
                onChanged: (v) => setS(() => partyId = v ?? ''),
              )
            else
              TextField(controller: other, decoration: InputDecoration(labelText: 'اتصرف لمين؟')),
            SizedBox(height: 10),
            numField(amount, 'المبلغ'),
            SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: method,
              decoration: InputDecoration(labelText: 'طريقة الدفع'),
              items: kPayMethods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setS(() => method = v ?? 'cash'),
            ),
            SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: 'البيان')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('حفظ')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final v = toD(amount.text);
  if (v <= 0) return;
  if (partyType == 'supplier' && partyId.isEmpty) {
    if (context.mounted) toast(context, 'اختار المورد', error: true);
    return;
  }
  await saveVoucher(
    partyType: partyType,
    partyId: partyType == 'supplier' ? partyId : '',
    partyName: partyType == 'supplier' ? (live.supplier(partyId)?.data()['name'] ?? '').toString() : other.text.trim(),
    amount: v,
    method: method,
    note: note.text.trim(),
    date: DateTime.now(),
  );
  if (context.mounted) toast(context, 'اتسجل سند الصرف');
}

class VouchersScreen extends StatelessWidget {
  const VouchersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final showOut = Me.can('purchases');
    final showIn = Me.can('sell');
    final tabs = [if (showIn) Tab(text: 'سندات التحصيل'), if (showOut) Tab(text: 'سندات الصرف')];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: pageAppBar(context, 'سندات التحصيل والصرف', bottom: TabBar(tabs: tabs)),
        body: TabBarView(children: [if (showIn) _ReceiptsTab(), if (showOut) _PaymentsTab()]),
      ),
    );
  }
}

class _ReceiptsTab extends StatelessWidget {
  const _ReceiptsTab();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        final list = live.entries.where((e) => e.kind == 'pay').toList()..sort((a, b) => b.date.compareTo(a.date));
        final now = DateTime.now();
        final today = list.where((e) => e.date.year == now.year && e.date.month == now.month && e.date.day == now.day);
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
           heroTag: null,
            heroTag: null,
            onPressed: () => pickCustomerThenPay(context),
            icon: Icon(Icons.add),
            label: Text('سند تحصيل'),
          ),
          body: ListView(padding: EdgeInsets.only(bottom: 90, top: 8), children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: StatBox('تحصيل النهارده (${today.length} سند)', money(today.fold(0.0, (a, e) => a + e.credit)),
                  color: kPaid, icon: Icons.savings_outlined),
            ),
            if (list.isEmpty) EmptyView('مفيش سندات تحصيل', icon: Icons.receipt_outlined),
            ...list.take(300).map((e) {
              final cid = (e.m['customerId'] ?? '').toString();
              final name = live.customerName(cid);
              final no = toI(e.m['receiptNo']);
              return Card(
                child: ListTile(
                  leading: Pill(no > 0 ? voucherLabel('in', no) : 'تحصيل', kPaid),
                  title: Text(name),
                  subtitle: Text('${fmtDate(e.date, time: true)} · ${payMethodLabel(e.m['method'])}'
                      '${e.by.isNotEmpty ? ' · ${e.by}' : ''}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(e.credit), style: TextStyle(fontWeight: FontWeight.bold, color: kPaid)),
                    IconButton(
                      tooltip: 'طباعة',
                      icon: Icon(Icons.print_outlined, size: 20),
                      onPressed: () => shareVoucherPdf(context,
                          title: 'سند تحصيل',
                          no: no > 0 ? voucherLabel('in', no) : '—',
                          party: name,
                          amount: e.credit,
                          method: payMethodLabel(e.m['method']),
                          note: e.note,
                          date: e.date,
                          balance: cid == kCashId ? null : live.accountOf(cid).balance),
                    ),
                  ]),
                  onTap: cid == kCashId
                      ? null
                      : () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => CustomerDetail(customerId: cid))),
                ),
              );
            }),
          ]),
        );
      },
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final list = Live.I.vouchers;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
           heroTag: null,
            heroTag: null,
            onPressed: () => voucherForm(context),
            icon: Icon(Icons.add),
            label: Text('سند صرف'),
          ),
          body: list.isEmpty
              ? EmptyView('مفيش سندات صرف', text: 'سجّل الفلوس اللي بتدفعها للموردين أو لأي جهة.', icon: Icons.outbox_outlined)
              : ListView(
                  padding: EdgeInsets.only(bottom: 90, top: 8),
                  children: list.map((v) {
                    final m = v.data();
                    return Card(
                      child: ListTile(
                        leading: Pill(voucherLabel('out', toI(m['no'])), kOwe),
                        title: Text((m['partyName'] ?? '').toString().isEmpty ? '—' : m['partyName'].toString()),
                        subtitle: Text('${fmtDate(m['date'])} · ${payMethodLabel(m['method'])}'
                            '${(m['note'] ?? '').toString().isEmpty ? '' : ' · ${m['note']}'}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(money(m['amount']), style: TextStyle(fontWeight: FontWeight.bold, color: kOwe)),
                          IconButton(
                            icon: Icon(Icons.print_outlined, size: 20),
                            onPressed: () => shareVoucherPdf(context,
                                title: 'سند صرف',
                                no: voucherLabel('out', toI(m['no'])),
                                party: (m['partyName'] ?? '').toString(),
                                amount: toD(m['amount']),
                                method: payMethodLabel(m['method']),
                                note: (m['note'] ?? '').toString(),
                                date: tsToDate(m['date']) ?? DateTime.now()),
                          ),
                          if (Me.owner)
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 20, color: kOwe),
                              onPressed: () async {
                                if (await confirm(context, 'حذف السند؟', 'هيتشال من حساب المورد.', ok: 'احذف', danger: true)) {
                                  await db.collection('vouchers').doc(v.id).delete();
                                }
                              },
                            ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}

// ======================== المصروفات ========================

Future<void> openExpenseForm(BuildContext context, {Doc? doc}) async {
  final live = Live.I;
  final m = doc?.data() ?? {};
  final cats = live.settings.expenseCats;
  var cat = (m['category'] ?? cats.first).toString();
  if (!cats.contains(cat)) cats.add(cat);
  final amount = TextEditingController(text: m['amount'] == null ? '' : num2(m['amount']).replaceAll(',', ''));
  final note = TextEditingController(text: (m['note'] ?? '').toString());
  var method = (m['method'] ?? 'cash').toString();
  var date = tsToDate(m['date']) ?? DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text(doc == null ? 'مصروف جديد' : 'تعديل مصروف'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: cat,
              decoration: InputDecoration(labelText: 'البند'),
              items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setS(() => cat = v ?? cat),
            ),
            SizedBox(height: 10),
            numField(amount, 'المبلغ', autofocus: doc == null),
            SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: method,
              decoration: InputDecoration(labelText: 'اتدفع إزاي'),
              items: kPayMethods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setS(() => method = v ?? 'cash'),
            ),
            SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: 'تفاصيل')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('التاريخ: ${fmtDate(date)}'),
              trailing: TextButton(
                onPressed: () async {
                  final x = await showDatePicker(
                      context: d, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (x != null) setS(() => date = x);
                },
                child: Text('تغيير'),
              ),
            ),
          ]),
        ),
        actions: [
          if (doc != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: kOwe),
              onPressed: () async {
                await db.collection('expenses').doc(doc.id).delete();
                if (d.mounted) Navigator.pop(d, false);
              },
              child: Text('حذف'),
            ),
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('حفظ')),
        ],
      ),
    ),
  );
  if (ok != true || toD(amount.text) <= 0) return;
  await saveExpense(
      id: doc?.id, category: cat, amount: toD(amount.text), method: method, note: note.text.trim(), date: date);
}

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final list = Live.I.expenses.where((x) {
          final d = tsToDate(x.data()['date']);
          return d != null && d.year == month.year && d.month == month.month;
        }).toList();
        final total = list.fold(0.0, (a, x) => a + toD(x.data()['amount']));
        final byCat = <String, double>{};
        for (final x in list) {
          final c = (x.data()['category'] ?? '').toString();
          byCat[c] = (byCat[c] ?? 0) + toD(x.data()['amount']);
        }
        final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return Scaffold(
          appBar: pageAppBar(context, 'المصروفات'),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => openExpenseForm(context),
            icon: Icon(Icons.add),
            label: Text('مصروف'),
          ),
          body: ListView(padding: EdgeInsets.only(bottom: 90), children: [
            Padding(
              padding: EdgeInsets.all(8),
              child: Row(children: [
                IconButton(
                    icon: Icon(Icons.chevron_right),
                    onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
                Expanded(
                    child: Text('${month.month}/${month.year}',
                        textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                IconButton(
                    icon: Icon(Icons.chevron_left),
                    onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
              ]),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: StatBox('مصروفات الشهر', money(total), color: kOwe, icon: Icons.account_balance_wallet_outlined),
            ),
            if (cats.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in cats) Chip(label: Text('${c.key}: ${num2(c.value)}')),
                ]),
              ),
            SizedBox(height: 6),
            if (list.isEmpty) EmptyView('مفيش مصروفات الشهر ده', icon: Icons.receipt_outlined),
            ...list.map((x) {
              final m = x.data();
              return Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: kBlush, child: Icon(Icons.receipt_outlined, color: kInk)),
                  title: Text((m['category'] ?? '').toString()),
                  subtitle: Text('${fmtDate(m['date'])} · ${payMethodLabel(m['method'])}'
                      '${(m['note'] ?? '').toString().isEmpty ? '' : ' · ${m['note']}'}'),
                  trailing: Text(money(m['amount']), style: TextStyle(fontWeight: FontWeight.bold, color: kOwe)),
                  onTap: () => openExpenseForm(context, doc: x),
                ),
              );
            }),
          ]),
        );
      },
    );
  }
}
