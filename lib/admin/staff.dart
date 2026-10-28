import 'package:flutter/material.dart';

import '../core.dart';
import 'accounts.dart' show showCredentials;
import 'live.dart';

/// المساعدين والموظفين: صاحب المحل بس اللي يشوف الشاشة دي
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final list = Live.I.staff;
        return Scaffold(
          appBar: AppBar(title: const Text('المساعدين والموظفين')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffForm())),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('موظف جديد'),
          ),
          body: list.isEmpty
              ? const EmptyView('مفيش موظفين لسه',
                  text: 'ضيف مساعد برقم موبايله وكلمة سر، واختار هو يقدر يعمل إيه.',
                  icon: Icons.badge_outlined)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 90),
                  children: list.map((u) {
                    final m = u.data();
                    final perms = ((m['perms'] as List?) ?? []).map((e) => e.toString()).toList();
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: kBlush, child: Icon(Icons.badge_outlined, color: kPlum)),
                        title: Row(children: [
                          Flexible(child: Text((m['name'] ?? '').toString(), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          if (m['disabled'] == true) const Pill('موقوف', kOwe),
                        ]),
                        subtitle: Text(
                            '${m['phone'] ?? ''}\n${perms.map((p) => kPerms[p] ?? p).join('، ')}',
                            style: const TextStyle(fontSize: 12)),
                        isThreeLine: true,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StaffForm(u: u))),
                      ),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}

class StaffForm extends StatefulWidget {
  final Doc? u;
  const StaffForm({super.key, this.u});
  @override
  State<StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<StaffForm> {
  late final m = widget.u?.data() ?? {};
  late final name = TextEditingController(text: (m['name'] ?? '').toString());
  late final phone = TextEditingController(text: (m['phone'] ?? '').toString());
  final pass = TextEditingController(text: randomPassword());
  late final Set<String> perms = widget.u == null
      ? kDefaultStaffPerms.toSet()
      : ((m['perms'] as List?) ?? []).map((e) => e.toString()).toSet();
  bool busy = false;

  bool get isNew => widget.u == null;

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.isEmpty) {
      toast(context, 'اكتب اسم الموظف', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      if (isNew) {
        if (!validPhone(phone.text)) throw 'رقم الموبايل مش صحيح';
        if (pass.text.length < 6) throw 'كلمة السر 6 حروف أو أرقام على الأقل';
        if (Live.I.customerForPhone(phone.text) != null || Live.I.userForPhone(phone.text) != null) {
          // مسموح، بس ننبّه إن الرقم ده متسجل كعميل
          if (!mounted) return;
          final ok = await confirm(context, 'الرقم ده متسجل كعميل',
              'لو كمّلت، الرقم ده هيدخل كموظف. لو العميل عنده حساب في التطبيق لازم تحذفه الأول.',
              ok: 'كمّل');
          if (!ok) {
            setState(() => busy = false);
            return;
          }
        }
        await createAccount(phone.text, n, pass.text, role: 'staff', perms: perms.toList());
        if (!mounted) return;
        await showCredentials(context, n, phone.text, pass.text);
        if (mounted) Navigator.pop(context);
      } else {
        await db.collection('users').doc(widget.u!.id).update({'name': n, 'perms': perms.toList()});
        if (!mounted) return;
        Navigator.pop(context);
        toast(context, 'اتحفظت الصلاحيات');
      }
    } catch (e) {
      if (mounted) toast(context, e is String ? e : authError(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _changePass() async {
    final c = TextEditingController(text: randomPassword());
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('كلمة سر جديدة'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'كلمة السر')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('غيّر')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (c.text.length < 6) {
      toast(context, 'كلمة السر 6 حروف أو أرقام على الأقل', error: true);
      return;
    }
    try {
      await changeAccountPassword(widget.u!.id, m, c.text);
      if (mounted) await showCredentials(context, name.text, phone.text, c.text);
    } catch (e) {
      if (mounted) toast(context, 'ماقدرتش أغيّرها: ${authError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'موظف جديد' : 'بيانات الموظف')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          enabled: isNew,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'رقم الموبايل (بيدخل بيه)'),
        ),
        if (isNew) ...[
          const SizedBox(height: 12),
          TextField(controller: pass, decoration: const InputDecoration(labelText: 'كلمة السر')),
        ],
        const SizedBox(height: 20),
        const Text('يقدر يعمل إيه؟', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPlum)),
        ...kPerms.entries.map((p) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: perms.contains(p.key),
              onChanged: (v) => setState(() {
                if (v == true) {
                  perms.add(p.key);
                } else {
                  perms.remove(p.key);
                }
              }),
              title: Text(p.value),
            )),
        const Text('حسابات العملاء والموظفين، أسعار الشرا، والإعدادات ليك إنت بس.',
            style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : _save,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(isNew ? 'اعمل الحساب' : 'حفظ'),
        ),
        if (!isNew) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: _changePass, icon: const Icon(Icons.key_outlined), label: const Text('تغيير كلمة السر')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await db.collection('users').doc(widget.u!.id).update({'disabled': m['disabled'] != true});
              if (mounted) Navigator.pop(context);
            },
            icon: Icon(m['disabled'] == true ? Icons.lock_open : Icons.lock_outline),
            label: Text(m['disabled'] == true ? 'تفعيل الحساب' : 'إيقاف الحساب'),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: kOwe),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (!await confirm(context, 'حذف ${m['name']}؟', 'مش هيقدر يدخل التطبيق تاني.',
                  ok: 'احذف', danger: true)) {
                return;
              }
              await deleteAccount(widget.u!.id, m);
              nav.pop();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف الموظف'),
          ),
        ],
      ]),
    );
  }
}
