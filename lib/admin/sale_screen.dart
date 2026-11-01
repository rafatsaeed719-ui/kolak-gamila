import 'package:flutter/material.dart';

import '../core.dart';
import '../ops.dart';
import '../pdf.dart';
import 'invoice_view.dart';
import 'live.dart';
import 'money_screens.dart';
import 'shell.dart';

/// بيع / مديونية: اختيار المنتجات بالدوس، كميات، دفعة، صور
class SaleScreen extends StatefulWidget {
  final String? customerId; // من غير عميل = بيع نقدي
  final Entry? old;
  final bool embedded; // صفحة «فاتورة بيع» في القايمة
  final VoidCallback? onSaved;
  const SaleScreen({super.key, this.customerId, this.old, this.embedded = false, this.onSaved});
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  late final List<SaleLine> lines =
      (widget.old?.items ?? []).map(SaleLine.fromMap).toList();
  late final List<String> photos = [...(widget.old?.photos ?? [])];
  late final extra = TextEditingController(
      text: toD(widget.old?.m['extra']) > 0 ? num2(widget.old!.m['extra']).replaceAll(',', '') : '');
  late final paid = TextEditingController(
      text: (widget.old?.credit ?? 0) > 0 ? num2(widget.old!.credit).replaceAll(',', '') : '');
  late final note = TextEditingController(text: widget.old?.note ?? '');
  late DateTime date = widget.old?.date ?? DateTime.now();
  late final discount = TextEditingController(
      text: (widget.old?.discount ?? 0) > 0 ? num2(widget.old!.discount).replaceAll(',', '') : '');
  late String payMethod = widget.old?.payMethod ?? 'cash';
  late String rep = widget.old?.rep ?? (Me.owner ? '' : Me.name);
  late String? cid = (widget.customerId == null || widget.customerId == kCashId) ? null : widget.customerId;
  String q = '';
  bool busy = false;

  double get itemsTotal => lines.fold(0.0, (a, l) => a + l.total);

  double qtyOf(String pid) =>
      lines.where((l) => l.productId == pid).fold(0.0, (a, l) => a + l.qty);

  void _addProduct(Doc p) {
    final m = p.data();
    final existing = lines.where((l) => l.productId == p.id).toList();
    setState(() {
      if (existing.isNotEmpty) {
        existing.first.qty += 1;
      } else {
        lines.add(SaleLine(
          productId: p.id,
          name: (m['name'] ?? '').toString(),
          code: (m['code'] ?? '').toString(),
          price: toD(m['price']),
        ));
      }
    });
  }

  Future<void> _addFree() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('صنف مش في القايمة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: 'اسم الصنف')),
          SizedBox(height: 10),
          numField(price, 'السعر'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('إضافة')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      setState(() => lines.add(SaleLine(name: name.text.trim(), price: toD(price.text))));
    }
  }

  Future<void> _editLine(SaleLine l) async {
    final qty = TextEditingController(text: num2(l.qty).replaceAll(',', ''));
    final price = TextEditingController(text: num2(l.price).replaceAll(',', ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          numField(qty, 'الكمية'),
          SizedBox(height: 10),
          numField(price, 'سعر القطعة'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('تمام')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        l.qty = toD(qty.text);
        l.price = toD(price.text);
        if (l.qty <= 0) lines.remove(l);
      });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) setState(() => date = DateTime(d.year, d.month, d.day, date.hour, date.minute));
  }

  Future<void> _save() async {
    final c = cid == null ? null : Live.I.customer(cid!);
    final ex = toD(extra.text), disc = toD(discount.text);
    var pd = toD(paid.text);
    final net = itemsTotal + ex - disc;
    if (cid == null && paid.text.trim().isEmpty) pd = net; // البيع النقدي بيتدفع كله
    if (disc < 0 || disc > itemsTotal + ex) {
      toast(context, 'الخصم أكبر من الفاتورة', error: true);
      return;
    }
    if (cid == null && pd < net - 0.004) {
      toast(context, 'البيع النقدي لازم يتدفع كله. اختار عميل لو هيبقى عليه باقي.', error: true);
      return;
    }
    if (itemsTotal + ex <= 0 && pd <= 0) {
      toast(context, 'اختار أصناف أو اكتب مبلغ', error: true);
      return;
    }
    if (itemsTotal + ex <= 0) {
      toast(context, 'لو هو دافع بس، سجّلها من «تسجيل دفعة»', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      if (cid == null) await ensureCashCustomer();
      final id = await saveSale(
        customerId: cid ?? kCashId,
        phone: (c?.data()['phone'] ?? '').toString(),
        lines: lines,
        extra: ex,
        paid: pd,
        discount: disc,
        payMethod: pd > 0 ? payMethod : 'cash',
        rep: rep,
        note: note.text.trim(),
        photos: photos,
        date: date,
        old: widget.old,
      );
      if (!mounted) return;
      if (!widget.embedded) {
        Navigator.pop(context);
        toast(context, widget.old == null ? 'اتسجل البيع' : 'اتعدلت الفاتورة');
        return;
      }
      await _afterSave(id);
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _afterSave(String id) async {
    Entry? found;
    for (final x in Live.I.entries) {
      if (x.id == id) found = x;
    }
    final e = found;
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        icon: Icon(Icons.check_circle, color: kPaid, size: 44),
        title: Text('اتسجلت الفاتورة ${e == null ? '' : invoiceLabel(e.invoiceNo)}'),
        content: Text(e == null ? '' : 'الصافي ${money(e.debit)} · الباقي ${money(e.remaining)}'),
        actions: [
          if (e != null)
            TextButton.icon(
              onPressed: () {
                final cust = Live.I.customer((e.m['customerId'] ?? '').toString())?.data() ?? {'name': 'نقدي', 'code': 0};
                shareInvoicePdf(d, cust, e);
              },
              icon: Icon(Icons.print_outlined),
              label: Text('اطبع الفاتورة'),
            ),
          if (e != null)
            TextButton(
              onPressed: () {
                Navigator.pop(d);
                openInvoice(context, e);
              },
              child: Text('افتح الفاتورة'),
            ),
          FilledButton(onPressed: () => Navigator.pop(d), child: Text('فاتورة جديدة')),
        ],
      ),
    );
  }

  Widget _customerBar() {
    final live = Live.I;
    final c = cid == null ? null : live.customer(cid!);
    final bal = cid == null ? 0.0 : live.accountOf(cid!).balance;
    return Card(
      margin: EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: kBlush,
          child: Icon(c == null ? Icons.payments_outlined : Icons.person_outline, color: kInk),
        ),
        title: Text(c == null ? 'بيع نقدي (من غير عميل)' : (c.data()['name'] ?? '').toString(),
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(c == null
            ? 'لو العميل هياخد ويدفع بعدين، اختاره'
            : '#${pad4(c.data()['code'])}${bal > 0.004 ? ' · عليه ${money(bal)}' : ''}'),
        trailing: widget.old != null
            ? null
            : Wrap(children: [
                if (c != null)
                  IconButton(tooltip: 'بيع نقدي', onPressed: () => setState(() => cid = null), icon: Icon(Icons.close)),
                TextButton(
                  onPressed: () async {
                    final x = await pickCustomer(context);
                    if (x != null) setState(() => cid = x.id);
                  },
                  child: Text(c == null ? 'اختار عميل' : 'غيّر'),
                ),
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = cid == null ? null : Live.I.customer(cid!);
    final acc = Live.I.accountOf(cid ?? '__none__');
    final cur = acc.balance - (widget.old == null ? 0 : widget.old!.debit - widget.old!.credit);
    final ex = toD(extra.text), disc = toD(discount.text);
    final net = itemsTotal + ex - disc;
    final pd = (cid == null && paid.text.trim().isEmpty) ? net : toD(paid.text);
    final after = cur + net - pd;
    final reps = <String>{'', ...Live.I.staffNames, if (!Me.owner) Me.name, if (rep.isNotEmpty) rep}.toList();
    final query = q.trim().toLowerCase();
    final prods = Live.I.products.where((p) {
      final m = p.data();
      if (query.isEmpty) return true;
      return (m['name'] ?? '').toString().toLowerCase().contains(query) ||
          (m['code'] ?? '').toString().toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: widget.embedded
          ? pageAppBar(context, 'فاتورة بيع')
          : AppBar(
              title: Text('${widget.old == null ? 'بيع' : 'تعديل ${invoiceLabel(widget.old!.invoiceNo)}'} — ${c?.data()['name'] ?? 'نقدي'}')),
      body: ListView(padding: EdgeInsets.only(bottom: 120), children: [
        if (widget.embedded || widget.customerId == null || widget.old != null) _customerBar(),
        SectionTitle('اختار المنتجات (كل دوسة = قطعة)',
            trailing: TextButton.icon(
                onPressed: _addFree, icon: Icon(Icons.add), label: Text('صنف تاني'))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: InputDecoration(
                hintText: 'دوّر باسم المنتج أو الكود', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        SizedBox(height: 8),
        if (Live.I.products.isEmpty)
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('مفيش منتجات متسجلة. ضيفها من «البضاعة» أو استخدم «صنف تاني».',
                style: TextStyle(color: kMuted)),
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 12),
              itemCount: prods.length,
              separatorBuilder: (_, __) => SizedBox(width: 8),
              itemBuilder: (_, i) => _tile(prods[i]),
            ),
          ),
        SectionTitle('اللي اشتراه'),
        if (lines.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('لسه مااخترتش أصناف.', style: TextStyle(color: kMuted)),
          ),
        ...lines.map((l) => Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _editLine(l),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('${num2(l.price)} ج للقطعة  ·  دوس للتعديل',
                            style: TextStyle(fontSize: 12, color: kMuted)),
                      ]),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      l.qty -= 1;
                      if (l.qty <= 0) lines.remove(l);
                    }),
                  ),
                  Text(num2(l.qty), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline, color: kInk),
                    onPressed: () => setState(() => l.qty += 1),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(num2(l.total),
                        textAlign: TextAlign.left, style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            )),
        SectionTitle('المبالغ'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            Row(children: [
              Expanded(child: numField(discount, 'خصم (ج)', onChanged: (_) => setState(() {}))),
              SizedBox(width: 10),
              Expanded(child: numField(extra, 'مديونية يدوي', onChanged: (_) => setState(() {}))),
            ]),
            SizedBox(height: 10),
            numField(paid, cid == null ? 'دفع كام؟ (فاضي = الصافي كله)' : 'دفع كام دلوقتي؟', onChanged: (_) => setState(() {})),
            SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: payMethod,
                  decoration: InputDecoration(labelText: 'طريقة الدفع'),
                  items: kPayMethods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setState(() => payMethod = v ?? 'cash'),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: rep,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'المندوب'),
                  items: reps.map((r) => DropdownMenuItem(value: r, child: Text(r.isEmpty ? 'بدون' : r))).toList(),
                  onChanged: (v) => setState(() => rep = v ?? ''),
                ),
              ),
            ]),
            SizedBox(height: 10),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: InputDecoration(labelText: 'ملاحظات (المبلغ ده بتاع إيه؟)'),
            ),
            SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event),
              title: Text('التاريخ: ${fmtDate(date)}'),
              trailing: TextButton(onPressed: _pickDate, child: Text('تغيير')),
            ),
          ]),
        ),
        SectionTitle('صور الحاجة اللي خدها',
            trailing: TextButton.icon(
              onPressed: photos.length >= 4
                  ? null
                  : () async {
                      final b = await pickImageB64(context);
                      if (b != null) setState(() => photos.add(b));
                    },
              icon: Icon(Icons.add_a_photo_outlined),
              label: Text('صوّر'),
            )),
        if (photos.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < photos.length; i++)
                  Stack(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: B64Image(photos[i], width: 80, height: 80)),
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: InkWell(
                        onTap: () => setState(() => photos.removeAt(i)),
                        child: CircleAvatar(
                            radius: 11, backgroundColor: kOwe, child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
      ]),
      bottomSheet: Material(
        elevation: 8,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('الصافي: ${money(net)}${disc > 0 ? ' (خصم ${num2(disc)})' : ''}  ·  دفع ${money(pd)}',
                      style: TextStyle(fontSize: 12, color: kMuted)),
                  Text(cid == null ? (pd >= net - 0.004 ? 'بيع نقدي ✓' : 'لازم يدفع ${money(net)}') : 'هيبقى عليه ${money(after)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16, color: after > 0 ? kOwe : kPaid)),
                ]),
              ),
              FilledButton(
                onPressed: busy ? null : _save,
                style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                child: Text('حفظ'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tile(Doc p) {
    final m = p.data();
    final n = qtyOf(p.id);
    final stock = m['stock'] == null ? null : toD(m['stock']);
    return SizedBox(
      width: 112,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: n > 0 ? kInk : Color(0xFFEBDDE2), width: n > 0 ? 2 : 1),
        ),
        child: InkWell(
          onTap: () => _addProduct(p),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: B64Image(m['image']?.toString())),
              Padding(
                padding: EdgeInsets.fromLTRB(6, 4, 6, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((m['name'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('${num2(m['price'])} ج${stock != null ? ' · ${num2(stock)} متاح' : ''}',
                      style: TextStyle(fontSize: 11, color: kMuted)),
                ]),
              ),
            ]),
            if (n > 0)
              PositionedDirectional(
                top: 4,
                start: 4,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: kInk,
                  child: Text(num2(n), style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
