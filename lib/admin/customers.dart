import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core.dart';
import '../ops.dart';
import '../pdf.dart';
import 'accounts.dart';
import 'live.dart';
import 'payment_screen.dart';
import 'sale_screen.dart';

class CodeBadge extends StatelessWidget {
  final dynamic code;
  const CodeBadge(this.code, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: kBlush, borderRadius: BorderRadius.circular(8)),
        child: Text('#${pad4(code)}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: kPlum, fontWeight: FontWeight.bold, fontSize: 12)),
      );
}

// ======================== قايمة العملاء ========================

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String q = '';
  String sort = 'bal';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        final query = q.trim().toLowerCase().replaceAll('#', '');
        var rows = live.customers.map((c) => MapEntry(c, live.accountOf(c.id))).toList();
        if (query.isNotEmpty) {
          rows = rows.where((r) {
            final m = r.key.data();
            final code = toI(m['code']).toString();
            return (m['name'] ?? '').toString().toLowerCase().contains(query) ||
                code == query.replaceFirst(RegExp(r'^0+'), '') ||
                pad4(m['code']).contains(query) ||
                normPhone((m['phone'] ?? '').toString()).contains(normPhone(query).isEmpty ? '#' : normPhone(query));
          }).toList();
        }
        rows.sort((a, b) {
          switch (sort) {
            case 'code':
              return toI(a.key.data()['code']).compareTo(toI(b.key.data()['code']));
            case 'name':
              return (a.key.data()['name'] ?? '').toString().compareTo((b.key.data()['name'] ?? '').toString());
            case 'last':
              final da = a.value.entries.isEmpty ? DateTime(2000) : a.value.entries.first.date;
              final dbb = b.value.entries.isEmpty ? DateTime(2000) : b.value.entries.first.date;
              return dbb.compareTo(da);
          }
          return b.value.balance.compareTo(a.value.balance);
        });
        final total = rows.fold(0.0, (s, r) => s + (r.value.balance > 0 ? r.value.balance : 0));
        return Scaffold(
          appBar: AppBar(title: const Text('العملاء')),
          floatingActionButton: !Me.can('customers')
              ? null
              : FloatingActionButton.extended(
            onPressed: () => openCustomerForm(context),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('عميل جديد'),
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                        hintText: 'ابحث بالاسم أو الكود أو الرقم', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => q = v),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  initialValue: sort,
                  onSelected: (v) => setState(() => sort = v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'bal', child: Text('الأعلى مديونية')),
                    PopupMenuItem(value: 'code', child: Text('بالكود')),
                    PopupMenuItem(value: 'name', child: Text('بالاسم')),
                    PopupMenuItem(value: 'last', child: Text('آخر حركة')),
                  ],
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Text('${rows.length} عميل', style: const TextStyle(color: kMuted)),
                const Spacer(),
                if (Me.can('reports'))
                  Text('عليهم ${money(total)}',
                    style: const TextStyle(color: kOwe, fontWeight: FontWeight.bold)),
              ]),
            ),
            Expanded(
              child: live.customers.isEmpty
                  ? const EmptyView('مفيش عملاء لسه',
                      text: 'دوس «عميل جديد» وهياخد كود ثابت تلقائي.', icon: Icons.people_outline)
                  : rows.isEmpty
                      ? const EmptyView('مفيش نتيجة', text: 'جرّب اسم تاني أو رقم الكود.')
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 90),
                          itemCount: rows.length,
                          itemBuilder: (c, i) => _row(context, rows[i].key, rows[i].value),
                        ),
            ),
          ]),
        );
      },
    );
  }

  Widget _row(BuildContext context, Doc c, Account a) {
    final m = c.data();
    final b = a.balance;
    final hasApp = Live.I.userForPhone((m['phone'] ?? '').toString()) != null;
    return Card(
      child: ListTile(
        leading: CodeBadge(m['code']),
        title: Row(children: [
          Flexible(
              child: Text((m['name'] ?? '').toString(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          if (hasApp) ...[
            const SizedBox(width: 4),
            const Icon(Icons.phone_android, size: 15, color: kPaid),
          ],
        ]),
        subtitle: Text(
          [
            if ((m['phone'] ?? '').toString().isNotEmpty) m['phone'],
            if (a.entries.isNotEmpty) 'آخر حركة ${fmtDate(a.entries.first.date)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(num2(b.abs()),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: b > 0.004 ? kOwe : (b < -0.004 ? kPaid : kMuted))),
            Text(b > 0.004 ? 'عليه' : (b < -0.004 ? 'له رصيد' : 'خالص'),
                style: const TextStyle(fontSize: 11, color: kMuted)),
          ],
        ),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => CustomerDetail(customerId: c.id))),
      ),
    );
  }
}

// ======================== إضافة / تعديل عميل ========================

Future<void> openCustomerForm(BuildContext context, {Doc? c}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerForm(c: c)));

class CustomerForm extends StatefulWidget {
  final Doc? c;
  const CustomerForm({super.key, this.c});
  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  late final m = widget.c?.data() ?? {};
  late final name = TextEditingController(text: (m['name'] ?? '').toString());
  late final phone = TextEditingController(text: (m['phone'] ?? '').toString());
  late final address = TextEditingController(text: (m['address'] ?? '').toString());
  late final notes = TextEditingController(text: (m['notes'] ?? '').toString());
  final code = TextEditingController();
  final opening = TextEditingController();
  final openingNote = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.c != null) {
      code.text = toI(m['code']).toString();
    } else {
      nextCustomerCode().then((n) {
        if (mounted && code.text.isEmpty) setState(() => code.text = '$n');
      });
    }
  }

  Future<void> _save() async {
    final n = name.text.trim();
    final k = int.tryParse(code.text.trim()) ?? 0;
    final p = phone.text.trim().isEmpty ? '' : normPhone(phone.text);
    if (n.isEmpty) { toast(context, 'اكتب اسم العميل', error: true); return; }
    if (k <= 0) { toast(context, 'الكود لازم يكون رقم أكبر من صفر', error: true); return; }
    if (p.isNotEmpty && !validPhone(p)) {
      { toast(context, 'رقم الموبايل مش صحيح', error: true); return; }
    }
    setState(() => busy = true);
    try {
      if (await codeTaken(k, exceptId: widget.c?.id)) {
        throw 'الكود #${pad4(k)} مستخدم لعميل تاني';
      }
      final other = Live.I.customerForPhone(p);
      if (p.isNotEmpty && other != null && other.id != widget.c?.id) {
        throw 'الرقم ده متسجل للعميل ${other.data()['name']} (#${pad4(other.data()['code'])})';
      }
      final data = {
        'name': n,
        'code': k,
        'phone': p,
        'address': address.text.trim(),
        'notes': notes.text.trim(),
      };
      if (widget.c == null) {
        final ref = db.collection('customers').doc();
        await ref.set({...data, 'createdAt': FieldValue.serverTimestamp()});
        final open = toD(opening.text);
        if (open > 0) {
          await saveAdjust(
              customerId: ref.id,
              phone: p,
              delta: open,
              note: openingNote.text.trim().isEmpty ? 'مديونية سابقة' : openingNote.text.trim(),
              date: DateTime.now());
        }
        if (!mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => CustomerDetail(customerId: ref.id)));
        toast(context, 'اتضاف العميل #${pad4(k)}');
      } else {
        await db.collection('customers').doc(widget.c!.id).update(data);
        if (p != normPhone((m['phone'] ?? '').toString())) {
          await updateCustomerPhoneEverywhere(widget.c!.id, p);
        }
        if (!mounted) return;
        Navigator.pop(context);
        toast(context, 'اتحفظت البيانات');
      }
    } catch (e) {
      if (mounted) toast(context, e is String ? e : authError(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.c == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'عميل جديد' : 'تعديل بيانات العميل')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: code,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'الكود الثابت', prefixText: '# ', helperText: 'تقدر تغيّره، بس ميتكررش'),
        ),
        const SizedBox(height: 12),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
              labelText: 'رقم الموبايل / الواتساب',
              hintText: '01xxxxxxxxx',
              helperText: 'لو سجّل في التطبيق بنفس الرقم هيشوف حسابه على طول'),
        ),
        const SizedBox(height: 12),
        TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان (اختياري)')),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات عن العميل'),
        ),
        if (isNew) ...[
          const SizedBox(height: 20),
          const Text('مديونية قديمة (اختياري)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          numField(opening, 'المبلغ اللي عليه من قبل كده'),
          const SizedBox(height: 12),
          TextField(
              controller: openingNote,
              decoration: const InputDecoration(labelText: 'المبلغ ده بتاع إيه؟')),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : _save,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('حفظ'),
        ),
        if (!isNew && Me.can('edit')) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: kOwe),
            onPressed: busy
                ? null
                : () async {
                    final nav = Navigator.of(context);
                    final ok = await confirm(context, 'حذف ${m['name']}؟',
                        'هيتحذف العميل وكل حركاته نهائي، والبضاعة اللي اتباعتله هترجع للمخزن.',
                        ok: 'احذف نهائي', danger: true);
                    if (!ok) return;
                    final acc = Live.I.accountOf(widget.c!.id);
                    for (final e in acc.entries) {
                      await deleteEntry(e, acc);
                    }
                    await db.collection('customers').doc(widget.c!.id).delete();
                    nav.popUntil((r) => r.isFirst);
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف العميل وكل حركاته'),
          ),
        ],
      ]),
    );
  }
}

// ======================== صفحة العميل ========================

class CustomerDetail extends StatelessWidget {
  final String customerId;
  const CustomerDetail({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        final c = live.customer(customerId);
        if (c == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const EmptyView('العميل ده مش موجود', text: 'ممكن يكون اتحذف.'));
        }
        final m = c.data();
        final phone = (m['phone'] ?? '').toString();
        final acc = live.accountOf(customerId);
        final appUser = live.userForPhone(phone);
        return Scaffold(
          appBar: AppBar(
            title: Text((m['name'] ?? '').toString()),
            actions: [
              if (Me.can('customers'))
              IconButton(
                tooltip: 'تعديل البيانات والكود',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => openCustomerForm(context, c: c),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CodeBadge(m['code']),
                    const SizedBox(width: 8),
                    if (phone.isNotEmpty)
                      Text(phone, textDirection: TextDirection.ltr, style: const TextStyle(color: kMuted)),
                    const Spacer(),
                    if (appUser != null)
                      const Pill('عنده التطبيق', kPaid)
                    else if (phone.isNotEmpty && Me.owner)
                      TextButton(
                        onPressed: () => openNewAccount(context, phone: phone, name: (m['name'] ?? '').toString()),
                        child: const Text('اعمله حساب'),
                      ),
                  ]),
                  if ((m['address'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(m['address'].toString(), style: const TextStyle(color: kMuted)),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    _box('إجمالي المسحوب', acc.debit, kOwe),
                    const SizedBox(width: 8),
                    _box('إجمالي المدفوع', acc.paid, kPaid),
                    const SizedBox(width: 8),
                    _box(acc.balance >= 0 ? 'الباقي عليه' : 'له رصيد', acc.balance.abs(),
                        acc.balance > 0.004 ? kOwe : kPaid),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.stars_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text('${acc.points} نقطة', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (acc.discounts > 0.004) ...[
                      const SizedBox(width: 12),
                      Text('خصومات: ${money(acc.discounts)}', style: const TextStyle(color: kMuted)),
                    ],
                    const Spacer(),
                    if (acc.points > 0 && Me.can('edit'))
                      TextButton(
                          onPressed: () => _redeem(context, c, acc), child: const Text('استبدال نقط')),
                  ]),
                  if ((m['notes'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kBlush, borderRadius: BorderRadius.circular(10)),
                      child: Text(m['notes'].toString()),
                    ),
                  ],
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (Me.can('sell'))
                FilledButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SaleScreen(customerId: customerId))),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('بيع / مديونية'),
                ),
                if (Me.can('sell'))
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => PaymentScreen(customerId: customerId))),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('تسجيل دفعة'),
                ),
                if (Me.can('edit'))
                OutlinedButton.icon(
                  onPressed: () => adjustSheet(context, c, acc),
                  icon: const Icon(Icons.tune),
                  label: const Text('تعديل الحساب'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: kPaid),
                  onPressed: phone.isEmpty
                      ? () => toast(context, 'ضيف رقم واتساب للعميل الأول', error: true)
                      : () => _whatsapp(context, c, acc),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('رسالة واتساب'),
                ),
                OutlinedButton.icon(
                  onPressed: () => shareStatementPdf(context, c.data(), acc),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('كشف حساب PDF'),
                ),
              ]),
            ),
            SectionTitle('سجل الحركات (${acc.entries.length})'),
            if (acc.entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('مفيش حركات لسه. سجّل اللي اشتراه من «بيع / مديونية».',
                    textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
              ),
            ...acc.entries.map((e) => EntryCard(e, admin: true, customer: c.data(), account: acc)),
          ]),
        );
      },
    );
  }

  Widget _box(String label, double v, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFF6EFF1), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
            FittedBox(
              child: Text(num2(v),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: color)),
            ),
          ]),
        ),
      );

  Future<void> _whatsapp(BuildContext context, Doc c, Account acc) async {
    final m = c.data();
    final name = (m['name'] ?? '').toString();
    final lastSale = acc.entries.where((e) => e.kind == 'sale').toList();
    String msg;
    if (acc.balance > 0.004) {
      final last = lastSale.isEmpty
          ? ''
          : '\nآخر سحب: ${money(lastSale.first.debit)} بتاريخ ${fmtDate(lastSale.first.date)}';
      msg = 'أهلاً $name 🌸\n'
          'ده كشف حسابك عند «$kStoreName» (كود #${pad4(m['code'])}):\n'
          'إجمالي المسحوب: ${money(acc.debit)}\n'
          'إجمالي المدفوع: ${money(acc.paid)}\n'
          '${acc.discounts > 0.004 ? 'خصومات: ${money(acc.discounts)}\n' : ''}'
          'المتبقي عليك: ${money(acc.balance)}$last\n\n'
          'برجاء تسديد المبلغ في أقرب وقت. شكراً لتعاملك معانا 💐';
    } else {
      msg = 'أهلاً $name 🌸\nحسابك عند «$kStoreName» خالص، مفيش عليك أي مبالغ. شكراً لتعاملك معانا 💐';
    }
    final ctl = TextEditingController(text: msg);
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c2) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c2).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('رسالة واتساب (تقدر تعدّلها)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(controller: ctl, maxLines: 10, minLines: 6),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kPaid),
            onPressed: () => Navigator.pop(c2, true),
            icon: const Icon(Icons.send),
            label: const Text('افتح واتساب'),
          ),
        ]),
      ),
    );
    if (send == true) await openWhatsApp((m['phone'] ?? '').toString(), ctl.text);
  }

  Future<void> _redeem(BuildContext context, Doc c, Account acc) async {
    final pts = TextEditingController(text: '${acc.points}');
    final val = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('استبدال نقط'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('عنده ${acc.points} نقطة'),
          const SizedBox(height: 10),
          TextField(
              controller: pts,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد النقط')),
          const SizedBox(height: 10),
          numField(val, 'قيمة الخصم بالجنيه (لو فيه)'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('استبدال')),
        ],
      ),
    );
    if (ok != true) return;
    final p = toI(pts.text);
    if (p <= 0 || p > acc.points) {
      if (context.mounted) toast(context, 'عدد النقط مش مظبوط', error: true);
      return;
    }
    await saveRedeem(
        customerId: c.id,
        phone: (c.data()['phone'] ?? '').toString(),
        points: p,
        value: toD(val.text),
        note: 'استبدال $p نقطة');
    if (context.mounted) toast(context, 'اتسجل الاستبدال');
  }
}

// ======================== تعديل الحساب ========================

Future<void> adjustSheet(BuildContext context, Doc c, Account acc, {Entry? old}) async {
  final cur = acc.balance - (old == null ? 0 : old.debit - old.credit);
  var mode = old == null ? 'add' : (old.debit > 0 ? 'add' : 'sub');
  final amount = TextEditingController(
      text: old == null ? '' : num2(old.debit > 0 ? old.debit : old.credit).replaceAll(',', ''));
  final note = TextEditingController(text: old?.note ?? '');
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sc) => StatefulBuilder(builder: (sc, setS) {
      final v = toD(amount.text);
      final d = round2(mode == 'add' ? v : (mode == 'sub' ? -v : v - cur));
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sc).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('تعديل حساب ${c.data()['name']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          Text('عليه دلوقتي: ${money(cur)}', style: const TextStyle(color: kMuted)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'add', label: Text('زوّد عليه')),
              const ButtonSegment(value: 'sub', label: Text('اخصم من عليه')),
              if (old == null) const ButtonSegment(value: 'set', label: Text('حدّد اللي عليه')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setS(() => mode = s.first),
          ),
          const SizedBox(height: 12),
          numField(amount,
              mode == 'add' ? 'المبلغ اللي هيتزوّد' : (mode == 'sub' ? 'المبلغ اللي هيتخصم' : 'المفروض يبقى عليه كام؟'),
              onChanged: (_) => setS(() {})),
          const SizedBox(height: 12),
          TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'السبب', hintText: 'خصم، مرتجع، تصحيح غلطة…')),
          const SizedBox(height: 12),
          Text('التغيير: ${d > 0 ? '+' : ''}${num2(d)}   ←   هيبقى عليه ${money(cur + d)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const Text('الخصم والتعديل مش بيتحسبوا فلوس اتحصّلت.',
              style: TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              if (d.abs() < 0.005) { toast(sc, 'مفيش تغيير في الحساب', error: true); return; }
              final nav = Navigator.of(sc);
              await saveAdjust(
                  customerId: c.id,
                  phone: (c.data()['phone'] ?? '').toString(),
                  delta: d,
                  note: note.text.trim().isEmpty ? (d > 0 ? 'زيادة على الحساب' : 'خصم من الحساب') : note.text.trim(),
                  date: old?.date ?? DateTime.now(),
                  old: old);
              nav.pop();
            },
            child: const Text('حفظ'),
          ),
        ]),
      );
    }),
  );
}

// ======================== كارت الحركة ========================

class EntryCard extends StatelessWidget {
  final Entry e;
  final bool admin;
  final Map<String, dynamic> customer;
  final Account account;
  const EntryCard(this.e,
      {super.key, required this.admin, required this.customer, required this.account});

  @override
  Widget build(BuildContext context) {
    final items = e.items;
    String label;
    Color color;
    switch (e.kind) {
      case 'pay':
        label = 'دفعة';
        color = kPaid;
        break;
      case 'adjust':
        label = 'تعديل حساب';
        color = kMuted;
        break;
      case 'redeem':
        label = 'استبدال ${toI(e.m['points'])} نقطة';
        color = Colors.amber.shade800;
        break;
      default:
        label = e.invoiceNo > 0 ? 'فاتورة #${e.invoiceNo}' : 'بيع';
        color = kOwe;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(label, color),
            const SizedBox(width: 8),
            Expanded(
                child: Text(fmtDate(e.date, time: true),
                    style: const TextStyle(fontSize: 12, color: kMuted))),
            if (e.debit > 0)
              Text('+${num2(e.debit)}', style: const TextStyle(color: kOwe, fontWeight: FontWeight.bold)),
            if (e.debit > 0 && e.credit > 0) const SizedBox(width: 8),
            if (e.credit > 0)
              Text('−${num2(e.credit)}',
                  style: TextStyle(
                      color: e.kind == 'adjust' || e.kind == 'redeem' ? kMuted : kPaid,
                      fontWeight: FontWeight.bold)),
          ]),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...items.map((it) {
              final total = round2(toD(it['qty']) * toD(it['price']));
              final paid = toD(it['paid']);
              final done = paid >= total - 0.004;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16, color: done ? kPaid : kRose),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${it['name']}  ×${num2(it['qty'])}')),
                  Text(num2(total)),
                  if (!done && paid > 0)
                    Text('  (باقي ${num2(total - paid)})',
                        style: const TextStyle(fontSize: 12, color: kOwe)),
                ]),
              );
            }),
          ],
          if (toD(e.m['extra']) > 0)
            Text('مديونية يدوي: ${money(e.m['extra'])}', style: const TextStyle(color: kMuted)),
          if (e.kind == 'sale' && e.credit > 0)
            Text('دفع وقتها: ${money(e.credit)}', style: const TextStyle(color: kPaid)),
          if (e.kind == 'pay' && e.allocations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${e.m['chosen'] == true ? 'دافع تمن' : 'اتحسبت على'}: ${e.allocations.map((a) => '${a['name']} (${num2(a['amount'])})').join('، ')}',
                style: const TextStyle(fontSize: 13, color: kMuted),
              ),
            ),
          if (e.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.note),
          ],
          if (admin && Me.owner && (e.m['by'] ?? '').toString().isNotEmpty && e.m['by'] != 'صاحب المحل')
            Text('سجّلها: ${e.m['by']}', style: const TextStyle(fontSize: 12, color: kMuted)),
          if (e.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: e.photos
                  .map((p) => InkWell(
                        onTap: () => showPhoto(context, p),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: B64Image(p, width: 64, height: 64)),
                      ))
                  .toList(),
            ),
          ],
          if (admin || e.kind == 'sale')
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (e.kind == 'sale')
                TextButton.icon(
                  onPressed: () => shareInvoicePdf(context, customer, e),
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('الفاتورة'),
                ),
              if (admin && e.kind == 'sale' && Me.can('edit'))
                TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SaleScreen(customerId: e.m['customerId'], old: e))),
                  child: const Text('تعديل'),
                ),
              if (admin && e.kind == 'adjust' && Me.can('edit'))
                TextButton(
                  onPressed: () {
                    final c = Live.I.customer(e.m['customerId']);
                    if (c != null) adjustSheet(context, c, account, old: e);
                  },
                  child: const Text('تعديل'),
                ),
              if (admin && Me.can('edit'))
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: kOwe),
                  onPressed: () async {
                    final ok = await confirm(
                        context,
                        'حذف الحركة دي؟',
                        e.kind == 'sale'
                            ? 'المبلغ هيتشال من حسابه والبضاعة هترجع للمخزن.'
                            : 'الحركة هتتشال من حسابه.',
                        ok: 'احذف',
                        danger: true);
                    if (!ok) return;
                    await deleteEntry(e, account);
                    if (context.mounted) toast(context, 'اتحذفت الحركة');
                  },
                  child: const Text('حذف'),
                ),
            ]),
        ]),
      ),
    );
  }
}
