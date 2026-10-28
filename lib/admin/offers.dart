import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core.dart';
import 'live.dart';

class OffersAdmin extends StatelessWidget {
  const OffersAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final list = Live.I.offers;
        return Scaffold(
          appBar: AppBar(title: const Text('العروض')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfferForm())),
            icon: const Icon(Icons.add),
            label: const Text('عرض جديد'),
          ),
          body: list.isEmpty
              ? const EmptyView('مفيش عروض',
                  text: 'العرض اللي تنزّله بيظهر للعملاء أول ما يفتحوا التطبيق، ويقدروا يطلبوه على طول.',
                  icon: Icons.local_offer_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final o = list[i];
                    final m = o.data();
                    final active = m['active'] != false && !offerExpired(m);
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => OfferForm(o: o))),
                        child: Row(children: [
                          B64Image(m['image']?.toString(), width: 90, height: 90, placeholder: Icons.local_offer_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((m['title'] ?? '').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('${money(m['price'])}${toD(m['oldPrice']) > 0 ? ' بدل ${money(m['oldPrice'])}' : ''}'),
                              Text('نزل ${fmtDate(m['createdAt'])}${m['until'] != null ? ' · لحد ${fmtDate(m['until'])}' : ''}',
                                  style: const TextStyle(fontSize: 12, color: kMuted)),
                            ]),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: active ? const Pill('شغال', kPaid) : const Pill('متوقف', Colors.grey),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

bool offerExpired(Map<String, dynamic> m) {
  final u = tsToDate(m['until']);
  return u != null && u.isBefore(DateTime.now());
}

class OfferForm extends StatefulWidget {
  final Doc? o;
  const OfferForm({super.key, this.o});
  @override
  State<OfferForm> createState() => _OfferFormState();
}

class _OfferFormState extends State<OfferForm> {
  late final m = widget.o?.data() ?? {};
  late final title = TextEditingController(text: (m['title'] ?? '').toString());
  late final body = TextEditingController(text: (m['body'] ?? '').toString());
  late final price = TextEditingController(text: m['price'] == null ? '' : num2(m['price']).replaceAll(',', ''));
  late final oldPrice =
      TextEditingController(text: toD(m['oldPrice']) > 0 ? num2(m['oldPrice']).replaceAll(',', '') : '');
  late String? image = m['image']?.toString();
  late String productId = (m['productId'] ?? '').toString();
  late bool active = m['active'] != false;
  late DateTime? until = tsToDate(m['until']);
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final prods = Live.I.products;
    return Scaffold(
      appBar: AppBar(title: Text(widget.o == null ? 'عرض جديد' : 'تعديل عرض')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        InkWell(
          onTap: () async {
            final b = await pickImageB64(context, maxWidth: 900);
            if (b != null) setState(() => image = b);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: image == null
                  ? Container(
                      color: kBlush,
                      alignment: Alignment.center,
                      child: const Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 40, color: kRose),
                        Text('صورة العرض (الإعلان)'),
                      ]),
                    )
                  : B64Image(image),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان العرض')),
        const SizedBox(height: 12),
        TextField(controller: body, maxLines: 3, decoration: const InputDecoration(labelText: 'تفاصيل العرض')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: prods.any((p) => p.id == productId) ? productId : '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'المنتج (عشان يتخصم من المخزن)'),
          items: [
            const DropdownMenuItem(value: '', child: Text('من غير منتج محدد')),
            ...prods.map((p) => DropdownMenuItem(value: p.id, child: Text((p.data()['name'] ?? '').toString()))),
          ],
          onChanged: (v) => setState(() {
            productId = v ?? '';
            final p = Live.I.product(productId);
            if (p != null) {
              if (oldPrice.text.isEmpty) oldPrice.text = num2(p.data()['price']).replaceAll(',', '');
              if (title.text.isEmpty) title.text = (p.data()['name'] ?? '').toString();
              image ??= p.data()['image']?.toString();
            }
          }),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: numField(price, 'سعر العرض')),
          const SizedBox(width: 10),
          Expanded(child: numField(oldPrice, 'السعر قبل العرض (اختياري)')),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(until == null ? 'من غير ميعاد انتهاء' : 'لحد ${fmtDate(until)}'),
          trailing: Wrap(children: [
            if (until != null) TextButton(onPressed: () => setState(() => until = null), child: const Text('شيل')),
            TextButton(
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: until ?? DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => until = DateTime(d.year, d.month, d.day, 23, 59));
              },
              child: const Text('حدّد'),
            ),
          ]),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: active,
          onChanged: (v) => setState(() => active = v),
          title: const Text('العرض شغال ويظهر للعملاء'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (title.text.trim().isEmpty) {
                    toast(context, 'اكتب عنوان العرض', error: true);
                    return;
                  }
                  setState(() => busy = true);
                  final data = {
                    'title': title.text.trim(),
                    'body': body.text.trim(),
                    'price': toD(price.text),
                    'oldPrice': toD(oldPrice.text),
                    'image': image,
                    'productId': productId,
                    'active': active,
                    'until': until == null ? null : Timestamp.fromDate(until!),
                  };
                  final nav = Navigator.of(context);
                  try {
                    if (widget.o == null) {
                      await db.collection('offers').add({...data, 'createdAt': FieldValue.serverTimestamp()});
                    } else {
                      await db.collection('offers').doc(widget.o!.id).update(data);
                    }
                    nav.pop();
                  } catch (e) {
                    if (context.mounted) toast(context, authError(e), error: true);
                    if (mounted) setState(() => busy = false);
                  }
                },
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(widget.o == null ? 'نزّل العرض' : 'حفظ'),
        ),
        if (widget.o != null)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: kOwe),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (await confirm(context, 'حذف العرض؟', 'هيختفي من عند العملاء.', ok: 'احذف', danger: true)) {
                await db.collection('offers').doc(widget.o!.id).delete();
                nav.pop();
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف العرض'),
          ),
      ]),
    );
  }
}
