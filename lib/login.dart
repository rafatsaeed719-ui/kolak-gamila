import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'core.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool register = false;
  bool busy = false;
  bool hide = true;
  final phone = TextEditingController();
  final name = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  String error = '';

  Future<void> _go() async {
    setState(() => error = '');
    final input = phone.text.trim();
    final isEmail = input.contains('@');
    if (isEmail && input.toLowerCase() != kAdminEmail.toLowerCase()) {
      setState(() => error = 'الدخول بالإيميل لصاحب المحل بس، ادخل برقم موبايلك');
      return;
    }
    if (!isEmail && !validPhone(input)) {
      setState(() => error = 'اكتب رقم موبايل صحيح زي 01012345678');
      return;
    }
    if (pass.text.length < 6) {
      setState(() => error = 'كلمة السر لازم تكون 6 حروف أو أرقام على الأقل');
      return;
    }
    if (register) {
      if (!isEmail && name.text.trim().isEmpty) {
        setState(() => error = 'اكتب اسمك');
        return;
      }
      if (pass.text != pass2.text) {
        setState(() => error = 'كلمتين السر مش زي بعض');
        return;
      }
    }
    setState(() => busy = true);
    try {
      if (register) {
        final cred = await auth.createUserWithEmailAndPassword(
            email: loginToEmail(input), password: pass.text);
        if (!isEmail) {
          await db.collection('users').doc(cred.user!.uid).set({
            'phone': normPhone(input),
            'name': name.text.trim(),
            'password': pass.text,
            'role': 'customer',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await auth.signInWithEmailAndPassword(email: loginToEmail(input), password: pass.text);
      }
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Image.asset('assets/logo.png', width: 200, height: 200)),
                const SizedBox(height: 12),
                const Text(kStoreName,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: kPlum)),
                const Text('العروض الجديدة كل يوم، وحسابك معاك على طول',
                    textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                const SizedBox(height: 24),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('دخول')),
                    ButtonSegment(value: true, label: Text('حساب جديد')),
                  ],
                  selected: {register},
                  onSelectionChanged: (s) => setState(() {
                    register = s.first;
                    error = '';
                  }),
                ),
                const SizedBox(height: 16),
                if (register) ...[
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                        labelText: 'الاسم', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      labelText: 'رقم الموبايل',
                      hintText: '01xxxxxxxxx',
                      prefixIcon: Icon(Icons.phone_iphone)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pass,
                  obscureText: hide,
                  decoration: InputDecoration(
                    labelText: 'كلمة السر',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => hide = !hide),
                    ),
                  ),
                  onSubmitted: (_) => register ? null : _go(),
                ),
                if (register) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass2,
                    obscureText: hide,
                    decoration: const InputDecoration(
                        labelText: 'أكّد كلمة السر', prefixIcon: Icon(Icons.lock_outline)),
                  ),
                ],
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(error, style: const TextStyle(color: kOwe)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : _go,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(register ? 'سجّل' : 'ادخل'),
                ),
                const SizedBox(height: 16),
                const Text('نسيت كلمة السر؟ كلّم المحل وهيغيّرهالك.',
                    textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// حساب دخول من غير ملف (نادر): بنكمّل البيانات
class CompleteProfile extends StatefulWidget {
  const CompleteProfile({super.key});
  @override
  State<CompleteProfile> createState() => _CompleteProfileState();
}

class _CompleteProfileState extends State<CompleteProfile> {
  final name = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final email = auth.currentUser?.email ?? '';
    final phone = email.split('@').first;
    return Scaffold(
      appBar: AppBar(title: const Text('كمّل بياناتك')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('رقمك: $phone', textDirection: TextDirection.ltr, textAlign: TextAlign.right),
        const SizedBox(height: 12),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (name.text.trim().isEmpty) return;
                  setState(() => busy = true);
                  try {
                    await db.collection('users').doc(uid).set({
                      'phone': normPhone(phone),
                      'name': name.text.trim(),
                      'role': 'customer',
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                  } catch (e) {
                    if (context.mounted) toast(context, authError(e), error: true);
                  }
                  if (mounted) setState(() => busy = false);
                },
          child: const Text('حفظ'),
        ),
        TextButton(onPressed: () => auth.signOut(), child: const Text('خروج')),
      ]),
    );
  }
}
