import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core.dart';
import 'customers.dart';
import 'live.dart';

String credentialsText(String name, String phone, String password) =>
    'أهلاً $name 🌸\nحسابك في تطبيق «$kStoreName» جاهز:\n'
    'رقم الموبايل: ${normPhone(phone)}\nكلمة السر: $password\n'
    'تقدر تشوف العروض كل يوم، وتطلب، وتتابع حسابك ونقطك.';

Future<void> showCredentials(BuildContext context, String name, String phone, String password) {
  final text = credentialsText(name, phone, password);
  return showDialog(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('بيانات الدخول'),
      content: SelectableText(text),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            toast(context, 'اتنسخت');
          },
          child: const Text('نسخ'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kPaid),
          onPressed: () => openWhatsApp(phone, text),
          icon: const Icon(Icons.send, size: 18),
          label: const Text('ابعتها واتساب'),
        ),
      ],
    ),
  );
}

Future<void> openNewAccount(BuildContext context, {String phone = '', String name = ''}) async {
  final p = TextEditingController(text: phone);
  final n = TextEditingController(text: name);
  final pass = TextEditingController(text: randomPassword());
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('حساب جديد لعميل'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 10),
        TextField(
            controller: p,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رقم الموبايل')),
        const SizedBox(height: 10),
        TextField(controller: pass, decoration: const InputDecoration(labelText: 'كلمة السر')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('اعمل الحساب')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (!validPhone(p.text)) {
    toast(context, 'رقم الموبايل مش صحيح', error: true);
    return;
  }
  if (pass.text.length < 6) {
    toast(context, 'كلمة السر 6 حروف أو أرقام على الأقل', error: true);
    return;
  }
  try {
    await createAccount(p.text, n.text.trim(), pass.text);
    if (context.mounted) await showCredentials(context, n.text.trim(), p.text, pass.text);
  } catch (e) {
    if (context.mounted) toast(context, authError(e), error: true);
  }
}

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final query = q.trim().toLowerCase();
        final list = Live.I.users.where((u) {
          final m = u.data();
          return query.isEmpty ||
              (m['name'] ?? '').toString().toLowerCase().contains(query) ||
              (m['phone'] ?? '').toString().contains(normPhone(query).isEmpty ? query : normPhone(query));
        }).toList()
          ..sort((a, b) => (tsToDate(b.data()['createdAt']) ?? DateTime(2000))
              .compareTo(tsToDate(a.data()['createdAt']) ?? DateTime(2000)));
        return Scaffold(
          appBar: AppBar(title: Text('حسابات التطبيق (${Live.I.users.length})')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => openNewAccount(context),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('حساب جديد'),
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(hintText: 'ابحث بالاسم أو الرقم', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyView('مفيش حسابات',
                      text: 'العملاء بيسجلوا من التطبيق برقم الموبايل، أو تعملهم إنت حساب.',
                      icon: Icons.manage_accounts_outlined)
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

  Widget _tile(BuildContext context, Doc u) {
    final m = u.data();
    final phone = (m['phone'] ?? '').toString();
    final cust = Live.I.customerForPhone(phone);
    final disabled = m['disabled'] == true;
    return Card(
      child: ListTile(
        title: Row(children: [
          Flexible(child: Text((m['name'] ?? '').toString(), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          if (disabled) const Pill('موقوف', kOwe),
        ]),
        subtitle: Text(
            '$phone  ·  ${cust == null ? 'مش في الدفتر' : 'كود #${pad4(cust.data()['code'])}'}  ·  سجّل ${fmtDate(m['createdAt'])}'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _action(context, v, u),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'show', child: Text('بيانات الدخول')),
            const PopupMenuItem(value: 'pass', child: Text('تغيير كلمة السر')),
            if (cust != null) const PopupMenuItem(value: 'open', child: Text('افتح حسابه')),
            PopupMenuItem(value: 'toggle', child: Text(disabled ? 'تفعيل الحساب' : 'إيقاف الحساب')),
            const PopupMenuItem(value: 'delete', child: Text('حذف الحساب', style: TextStyle(color: kOwe))),
          ],
        ),
      ),
    );
  }

  Future<void> _action(BuildContext context, String v, Doc u) async {
    final m = u.data();
    final name = (m['name'] ?? '').toString();
    final phone = (m['phone'] ?? '').toString();
    switch (v) {
      case 'show':
        final pass = (m['password'] ?? '').toString();
        if (pass.isEmpty) {
          toast(context, 'كلمة السر مش متسجلة، غيّرهاله عشان تبعتهاله', error: true);
          return;
        }
        await showCredentials(context, name, phone, pass);
        break;
      case 'open':
        final c = Live.I.customerForPhone(phone);
        if (c != null) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(customerId: c.id)));
        }
        break;
      case 'pass':
        final ctl = TextEditingController(text: randomPassword());
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('كلمة سر جديدة لـ $name'),
            content: TextField(controller: ctl, decoration: const InputDecoration(labelText: 'كلمة السر الجديدة')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('غيّر')),
            ],
          ),
        );
        if (ok != true || !context.mounted) return;
        if (ctl.text.length < 6) {
          toast(context, 'كلمة السر 6 حروف أو أرقام على الأقل', error: true);
          return;
        }
        try {
          await changeAccountPassword(u.id, m, ctl.text);
          if (context.mounted) await showCredentials(context, name, phone, ctl.text);
        } catch (e) {
          if (context.mounted) {
            toast(context, 'ماقدرتش أغيّرها (${authError(e)}). احذف الحساب واعمله واحد جديد.', error: true);
          }
        }
        break;
      case 'toggle':
        await db.collection('users').doc(u.id).update({'disabled': m['disabled'] != true});
        break;
      case 'delete':
        if (!await confirm(context, 'حذف حساب $name؟',
            'مش هيقدر يدخل التطبيق تاني بالحساب ده. حسابه في الدفتر (المديونيات) مش هيتمسح.',
            ok: 'احذف', danger: true)) {
          return;
        }
        final removed = await deleteAccount(u.id, m);
        if (context.mounted) toast(context, removed ? 'اتحذف الحساب' : 'الحساب اتوقف (مقدرتش أحذفه نهائي)');
        break;
    }
  }
}
