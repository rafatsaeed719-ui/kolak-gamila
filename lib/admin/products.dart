import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core.dart';
import 'live.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final all = Live.I.products;
        final query = q.trim().toLowerCase();
        final list = all.where((p) {
          final m = p.data();
          return query.isEmpty ||
              (m['name'] ?? '').toString().toLowerCase().contains(query) ||
              (m['code'] ?? '').toString().toLowerCase().contains(query);
        }).toList();
        var cost = 0.0, sell = 0.0;
        for (final p in all) {
          final s = toD(p.data()['stock']);
          if (s > 0) {
            cost += s * Live.I.costOf(p.id);
            sell += s * toD(p.data()['price']);
          }
        }
        return Scaffold(
          appBar: AppBar(title: const Text('البضاعة والمنتجات')),
          floatingActionButton: !Me.can('products')
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductForm())),
                  icon: const Icon(Icons.add),
                  label: const Text('منتج جديد'),
                ),
          body: Column(children: [
            if (Me.can('reports'))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Row(children: [
                  if (Me.owner)
                    Expanded(child: StatBox('رصيد البضاعة (شرا)', money(cost), icon: Icons.inventory_2_outlined)),
                  if (Me.owner) const SizedBox(width: 8),
                  Expanded(child: StatBox('رصيد البضاعة (بيع)', money(sell), icon: Icons.sell_outlined)),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(hintText: 'ابحث بالاسم أو الكود', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            Expanded(
              child: all.isEmpty
                  ? const EmptyView('مفيش منتجات لسه',
                      text: 'ضيف منتجاتك بالاسم والكود والسعر والصورة والكمية اللي في المحل.',
                      icon: Icons.inventory_2_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _tile(context, list[i]),
                    ),
            ),
          ]),
        );
      },
    );
  }

  Widget _tile(BuildContext context, Doc p) {
    final m = p.data();
    final stock = m['stock'] == null ? null : toD(m['stock']);
    final low = stock != null && stock <= toD(m['minStock'] ?? 2);
    return Card(
      child: ListTile(
        leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: B64Image(m['image']?.toString(), width: 52, height: 52)),
        title: Text((m['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if ((m['code'] ?? '').toString().isNotEmpty) m['code'],
          'بيع ${num2(m['price'])}',
          if (Live.I.costOf(p.id) > 0) 'شرا ${num2(Live.I.costOf(p.id))}',
          if (m['visible'] == false) 'مخفي من المعرض',
        ].join(' · ')),
        trailing: stock == null
            ? null
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(num2(stock),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: low ? kOwe : kPlum)),
                Text('في المحل', style: TextStyle(fontSize: 11, color: low ? kOwe : kMuted)),
              ]),
        onTap: !Me.can('products')
            ? null
            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(p: p))),
      ),
    );
  }
}

class ProductForm extends StatefulWidget {
  final Doc? p;
  const ProductForm({super.key, this.p});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  late final m = widget.p?.data() ?? {};
  late final name = TextEditingController(text: (m['name'] ?? '').toString());
  late final code = TextEditingController(text: (m['code'] ?? '').toString());
  late final price = TextEditingController(text: m['price'] == null ? '' : num2(m['price']).replaceAll(',', ''));
  late final cost = TextEditingController(
      text: widget.p == null || Live.I.costOf(widget.p!.id) == 0 ? '' : num2(Live.I.costOf(widget.p!.id)).replaceAll(',', ''));
  late final stock = TextEditingController(text: m['stock'] == null ? '' : num2(m['stock']).replaceAll(',', ''));
  late final minStock =
      TextEditingController(text: m['minStock'] == null ? '2' : num2(m['minStock']).replaceAll(',', ''));
  late final desc = TextEditingController(text: (m['desc'] ?? '').toString());
  late String? image = m['image']?.toString();
  late bool visible = m['visible'] != false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.p == null) {
      var n = 0;
      for (final p in Live.I.products) {
        final k = int.tryParse((p.data()['code'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (k > n) n = k;
      }
      code.text = 'P-${(n + 1).toString().padLeft(3, '0')}';
    }
  }

  Future<void> _addStock() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('بضاعة جديدة وصلت'),
        content: numField(c, 'الكمية اللي وصلت', autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (ok == true && toD(c.text) != 0 && widget.p != null) {
      await db.collection('products').doc(widget.p!.id).update({'stock': FieldValue.increment(toD(c.text))});
      setState(() => stock.text = num2(toD(stock.text) + toD(c.text)).replaceAll(',', ''));
      if (mounted) toast(context, 'اتزوّدت ${num2(c.text)} قطعة');
    }
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      toast(context, 'اكتب اسم المنتج', error: true);
      return;
    }
    setState(() => busy = true);
    final data = <String, dynamic>{
      'name': name.text.trim(),
      'code': code.text.trim(),
      'price': toD(price.text),
      'minStock': toD(minStock.text),
      'desc': desc.text.trim(),
      'image': image,
      'visible': visible,
      'stock': stock.text.trim().isEmpty ? null : toD(stock.text),
    };
    try {
      final ref = widget.p == null ? db.collection('products').doc() : db.collection('products').doc(widget.p!.id);
      if (widget.p == null) {
        await ref.set({...data, 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await ref.update(data);
      }
      // سعر الشرا في مكان منفصل عشان العملاء مايشوفوهوش
      if (Me.owner) await db.collection('productCosts').doc(ref.id).set({'cost': toD(cost.text)});
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'اتحفظ المنتج');
    } catch (e) {
      if (mounted) {
        toast(context, authError(e), error: true);
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.p == null ? 'منتج جديد' : 'تعديل منتج')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: InkWell(
            onTap: () async {
              final b = await pickImageB64(context);
              if (b != null) setState(() => image = b);
            },
            child: Stack(children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(16), child: B64Image(image, width: 140, height: 140)),
              const PositionedDirectional(
                  bottom: 6,
                  end: 6,
                  child: CircleAvatar(radius: 16, backgroundColor: kPlum, child: Icon(Icons.camera_alt, size: 16, color: Colors.white))),
            ]),
          ),
        ),
        if (image != null)
          Center(child: TextButton(onPressed: () => setState(() => image = null), child: const Text('شيل الصورة'))),
        const SizedBox(height: 12),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المنتج')),
        const SizedBox(height: 12),
        TextField(controller: code, decoration: const InputDecoration(labelText: 'الكود')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: numField(price, 'سعر البيع')),
          if (Me.owner) const SizedBox(width: 10),
          if (Me.owner) Expanded(child: numField(cost, 'سعر الشرا (ليك بس)')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: numField(stock, 'الكمية في المحل')),
          const SizedBox(width: 10),
          Expanded(child: numField(minStock, 'نبّهني لما توصل')),
        ]),
        if (widget.p != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
                onPressed: _addStock, icon: const Icon(Icons.add_box_outlined), label: const Text('بضاعة جديدة وصلت')),
          ),
        const SizedBox(height: 8),
        TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف يظهر للعملاء (اختياري)')),
        SwitchListTile(
          value: visible,
          onChanged: (v) => setState(() => visible = v),
          title: const Text('يظهر للعملاء في المعرض'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : _save,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('حفظ'),
        ),
        if (widget.p != null)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: kOwe),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (!await confirm(context, 'حذف المنتج؟', 'الفواتير القديمة اللي فيها المنتج ده هتفضل زي ما هي.',
                  ok: 'احذف', danger: true)) {
                return;
              }
              await db.collection('products').doc(widget.p!.id).delete();
              nav.pop();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف المنتج'),
          ),
      ]),
    );
  }
}
