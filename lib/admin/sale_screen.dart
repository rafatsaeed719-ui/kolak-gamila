import 'package:flutter/material.dart';

import '../core.dart';
import '../ops.dart';
import 'live.dart';

/// بيع / مديونية: اختيار المنتجات بالدوس، كميات، دفعة، صور
class SaleScreen extends StatefulWidget {
  final String customerId;
  final Entry? old;
  const SaleScreen({super.key, required this.customerId, this.old});
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
        title: const Text('صنف مش في القايمة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم الصنف')),
          const SizedBox(height: 10),
          numField(price, 'السعر'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('إضافة')),
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
          const SizedBox(height: 10),
          numField(price, 'سعر القطعة'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تمام')),
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
    final c = Live.I.customer(widget.customerId);
    if (c == null) return;
    final ex = toD(extra.text), pd = toD(paid.text);
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
      await saveSale(
        customerId: c.id,
        phone: (c.data()['phone'] ?? '').toString(),
        lines: lines,
        extra: ex,
        paid: pd,
        note: note.text.trim(),
        photos: photos,
        date: date,
        old: widget.old,
      );
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, widget.old == null ? 'اتسجل البيع' : 'اتعدلت الفاتورة');
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Live.I.customer(widget.customerId);
    final acc = Live.I.accountOf(widget.customerId);
    final cur = acc.balance - (widget.old == null ? 0 : widget.old!.debit - widget.old!.credit);
    final ex = toD(extra.text), pd = toD(paid.text);
    final after = cur + itemsTotal + ex - pd;
    final query = q.trim().toLowerCase();
    final prods = Live.I.products.where((p) {
      final m = p.data();
      if (query.isEmpty) return true;
      return (m['name'] ?? '').toString().toLowerCase().contains(query) ||
          (m['code'] ?? '').toString().toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
          title: Text('${widget.old == null ? 'بيع' : 'تعديل فاتورة'} — ${c?.data()['name'] ?? ''}')),
      body: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
        SectionTitle('اختار المنتجات (كل دوسة = قطعة)',
            trailing: TextButton.icon(
                onPressed: _addFree, icon: const Icon(Icons.add), label: const Text('صنف تاني'))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'دوّر باسم المنتج أو الكود', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        const SizedBox(height: 8),
        if (Live.I.products.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('مفيش منتجات متسجلة. ضيفها من «البضاعة» أو استخدم «صنف تاني».',
                style: TextStyle(color: kMuted)),
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: prods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _tile(prods[i]),
            ),
          ),
        const SectionTitle('اللي اشتراه'),
        if (lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('لسه مااخترتش أصناف.', style: TextStyle(color: kMuted)),
          ),
        ...lines.map((l) => Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _editLine(l),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${num2(l.price)} ج للقطعة  ·  دوس للتعديل',
                            style: const TextStyle(fontSize: 12, color: kMuted)),
                      ]),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      l.qty -= 1;
                      if (l.qty <= 0) lines.remove(l);
                    }),
                  ),
                  Text(num2(l.qty), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: kPlum),
                    onPressed: () => setState(() => l.qty += 1),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(num2(l.total),
                        textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            )),
        const SectionTitle('المبالغ'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            numField(extra, 'مديونية يدوي (مبلغ من غير أصناف)', onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            numField(paid, 'دفع كام دلوقتي؟', onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات (المبلغ ده بتاع إيه؟)'),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('التاريخ: ${fmtDate(date)}'),
              trailing: TextButton(onPressed: _pickDate, child: const Text('تغيير')),
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
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('صوّر'),
            )),
        if (photos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        child: const CircleAvatar(
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('الفاتورة: ${money(itemsTotal + ex)}  ·  دفع ${money(pd)}',
                      style: const TextStyle(fontSize: 12, color: kMuted)),
                  Text('هيبقى عليه ${money(after)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16, color: after > 0 ? kOwe : kPaid)),
                ]),
              ),
              FilledButton(
                onPressed: busy ? null : _save,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                child: const Text('حفظ'),
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
          side: BorderSide(color: n > 0 ? kPlum : const Color(0xFFEBDDE2), width: n > 0 ? 2 : 1),
        ),
        child: InkWell(
          onTap: () => _addProduct(p),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: B64Image(m['image']?.toString())),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((m['name'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('${num2(m['price'])} ج${stock != null ? ' · ${num2(stock)} متاح' : ''}',
                      style: const TextStyle(fontSize: 11, color: kMuted)),
                ]),
              ),
            ]),
            if (n > 0)
              PositionedDirectional(
                top: 4,
                start: 4,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: kPlum,
                  child: Text(num2(n), style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
