import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

// ======================== ثوابت ========================

/// إيميل صاحب المحل (المدير)
const String kAdminEmail = 'rafatsaeed719@gmail.com';
const String kStoreName = 'كلك جميلة';

/// حسابات العملاء بتتسجل داخلياً كـ 2010xxxxxxxx@kolak-gamila.app
const String kUserDomain = 'kolak-gamila.app';

const Color kPlum = Color(0xFF7A1F47);
const Color kRose = Color(0xFFC98A9E);
const Color kBlush = Color(0xFFF8EEF1);
const Color kOwe = Color(0xFFB4232F);
const Color kPaid = Color(0xFF1D7A52);
const Color kMuted = Color(0xFF7D6670);

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

String get uid => auth.currentUser?.uid ?? '';

bool get isAdmin =>
    (auth.currentUser?.email ?? '').toLowerCase() == kAdminEmail.toLowerCase();

// ======================== التليفون ========================

/// أي شكل للرقم المصري -> 01xxxxxxxxx (أو الأرقام زي ما هي لو مش مصري)
String normPhone(String input) {
  var d = input.replaceAll(RegExp(r'[^0-9٠-٩]'), '');
  const ar = '٠١٢٣٤٥٦٧٨٩';
  d = d.split('').map((c) {
    final i = ar.indexOf(c);
    return i >= 0 ? '$i' : c;
  }).join();
  if (d.startsWith('0020')) d = d.substring(4);
  if (d.startsWith('20') && d.length == 12) d = d.substring(2);
  if (d.length == 10 && d.startsWith('1')) d = '0$d';
  return d;
}

bool validPhone(String p) => RegExp(r'^01[0-9]{9}$').hasMatch(normPhone(p));

String phoneToEmail(String phone) => '${normPhone(phone)}@$kUserDomain';

/// اللي اتكتب في خانة الدخول: لو فيه @ يبقى إيميل (المدير)، غير كده رقم تليفون
String loginToEmail(String input) {
  final t = input.trim();
  return t.contains('@') ? t : phoneToEmail(t);
}

String waNumber(String phone) {
  final p = normPhone(phone);
  if (p.startsWith('0') && p.length == 11) return '2$p';
  return p;
}

Future<void> openWhatsApp(String phone, String text) async {
  final uri = Uri.parse('https://wa.me/${waNumber(phone)}?text=${Uri.encodeComponent(text)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> callPhone(String phone) async {
  await launchUrl(Uri.parse('tel:${normPhone(phone)}'));
}

// ======================== أرقام وتواريخ ========================

double toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int toI(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double round2(double v) => (v * 100).roundToDouble() / 100;

String _two(int n) => n.toString().padLeft(2, '0');

/// 1234.5 -> "1,234.5"
String num2(dynamic v) {
  final d = round2(toD(v));
  final neg = d < 0;
  final abs = d.abs();
  final whole = abs.truncate();
  final frac = ((abs - whole) * 100).round();
  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  var out = buf.toString();
  if (frac > 0) out += '.${frac % 10 == 0 ? (frac ~/ 10).toString() : _two(frac)}';
  return '${neg ? '-' : ''}$out';
}

String money(dynamic v) => '${num2(v)} ج';

String pad4(dynamic n) => toI(n).toString().padLeft(4, '0');

DateTime? tsToDate(dynamic ts) {
  if (ts is Timestamp) return ts.toDate();
  if (ts is DateTime) return ts;
  return null;
}

String fmtDate(dynamic ts, {bool time = false}) {
  final d = tsToDate(ts);
  if (d == null) return '-';
  final date = '${d.year}/${_two(d.month)}/${_two(d.day)}';
  if (!time) return date;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$date  ${_two(h)}:${_two(d.minute)} ${d.hour < 12 ? 'ص' : 'م'}';
}

// ======================== الإعدادات ========================

class StoreSettings {
  final double pointThreshold; // أي عملية أكبر من (أو تساوي في الدفع) المبلغ ده = نقطة
  final String storePhone;
  final String storeAddress;
  const StoreSettings({this.pointThreshold = 200, this.storePhone = '', this.storeAddress = ''});

  factory StoreSettings.fromMap(Map<String, dynamic>? m) => StoreSettings(
        pointThreshold: toD(m?['pointThreshold'] ?? 200) <= 0 ? 200 : toD(m?['pointThreshold'] ?? 200),
        storePhone: (m?['storePhone'] ?? '').toString(),
        storeAddress: (m?['storeAddress'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'pointThreshold': pointThreshold,
        'storePhone': storePhone,
        'storeAddress': storeAddress,
      };

  String get rulesText =>
      'نقطة على كل فاتورة أكبر من ${num2(pointThreshold)} ج، ونقطة على كل دفعة ${num2(pointThreshold)} ج أو أكتر';
}

DocumentReference<Map<String, dynamic>> get settingsRef => db.collection('meta').doc('settings');
DocumentReference<Map<String, dynamic>> get countersRef => db.collection('meta').doc('counters');

Stream<StoreSettings> settingsStream() => settingsRef.snapshots().map((s) => StoreSettings.fromMap(s.data()));

// ======================== حساب العميل ========================

/// أنواع الحركات:
/// sale   = بيع / مديونية (debit) ممكن معاه دفعة (credit)
/// pay    = دفعة (credit) ممكن تكون متوزعة على أصناف معينة (allocations)
/// adjust = تعديل حساب: زيادة أو خصم (مش بيتحسب تحصيل)
/// redeem = استبدال نقط (points) وممكن معاه خصم فلوس (credit)
class Entry {
  final String id;
  final Map<String, dynamic> m;
  Entry(this.id, this.m);
  factory Entry.of(DocumentSnapshot<Map<String, dynamic>> d) => Entry(d.id, d.data() ?? {});

  String get kind => (m['kind'] ?? 'sale').toString();
  double get debit => toD(m['debit']);
  double get credit => toD(m['credit']);
  DateTime get date => tsToDate(m['date']) ?? DateTime(2000);
  String get note => (m['note'] ?? '').toString();
  List<Map<String, dynamic>> get items =>
      ((m['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  List<String> get photos => ((m['photos'] as List?) ?? []).map((e) => e.toString()).toList();
  List<Map<String, dynamic>> get allocations =>
      ((m['allocations'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  int get invoiceNo => toI(m['invoiceNo']);

  /// المبلغ اللي اتحصّل فعلاً (من غير الخصومات والنقط)
  double get collected => (kind == 'adjust' || kind == 'redeem') ? 0 : credit;
}

class Account {
  final List<Entry> entries;
  final StoreSettings settings;
  Account(this.entries, this.settings);

  double get debit => entries.fold(0.0, (a, e) => a + e.debit);
  double get credit => entries.fold(0.0, (a, e) => a + e.credit);
  double get paid => entries.fold(0.0, (a, e) => a + e.collected);
  double get discounts => credit - paid;
  double get balance => round2(debit - credit);

  int get pointsEarned {
    final t = settings.pointThreshold;
    var p = 0;
    for (final e in entries) {
      if (e.kind == 'sale' && e.debit > t) p++;
      if (e.collected >= t) p++;
    }
    return p;
  }

  int get pointsUsed =>
      entries.where((e) => e.kind == 'redeem').fold(0, (a, e) => a + toI(e.m['points']));
  int get points => pointsEarned - pointsUsed;

  /// الأصناف اللي لسه عليها فلوس (للدفع المتحدد على أصناف)
  List<OpenItem> get openItems {
    final out = <OpenItem>[];
    final sales = entries.where((e) => e.kind == 'sale').toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final s in sales) {
      final items = s.items;
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        final total = round2(toD(it['qty']) * toD(it['price']));
        final rem = round2(total - toD(it['paid']));
        if (rem > 0.004) out.add(OpenItem(s, i, it, total, rem));
      }
    }
    return out;
  }
}

class OpenItem {
  final Entry sale;
  final int index;
  final Map<String, dynamic> item;
  final double total;
  final double remaining;
  OpenItem(this.sale, this.index, this.item, this.total, this.remaining);
}

Query<Map<String, dynamic>> entriesOf(String customerId) =>
    db.collection('entries').where('customerId', isEqualTo: customerId);

// ======================== عدّادات ========================

Future<int> nextCounter(String field) async {
  return db.runTransaction<int>((tx) async {
    final s = await tx.get(countersRef);
    final n = toI(s.data()?[field]) + 1;
    tx.set(countersRef, {field: n}, SetOptions(merge: true));
    return n;
  });
}

/// أول كود فاضي بعد أكبر كود موجود
Future<int> nextCustomerCode() async {
  final q = await db.collection('customers').orderBy('code', descending: true).limit(1).get();
  if (q.docs.isEmpty) return 1;
  return toI(q.docs.first.data()['code']) + 1;
}

Future<bool> codeTaken(int code, {String? exceptId}) async {
  final q = await db.collection('customers').where('code', isEqualTo: code).limit(2).get();
  return q.docs.any((d) => d.id != exceptId);
}

/// العميل في الدفتر اللي ليه نفس رقم التليفون (أو بيعمله جديد)
Future<DocumentSnapshot<Map<String, dynamic>>> customerForPhone(String phone, String name) async {
  final p = normPhone(phone);
  final q = await db.collection('customers').where('phone', isEqualTo: p).limit(1).get();
  if (q.docs.isNotEmpty) return q.docs.first;
  final code = await nextCustomerCode();
  final ref = db.collection('customers').doc();
  await ref.set({
    'code': code,
    'name': name.isEmpty ? p : name,
    'phone': p,
    'address': '',
    'notes': 'اتضاف تلقائي من التطبيق',
    'createdAt': FieldValue.serverTimestamp(),
  });
  return ref.get();
}

/// تغيير رقم تليفون العميل في الدفتر بيغيّره في كل حركاته (عشان يفضل شايفها)
Future<void> updateCustomerPhoneEverywhere(String customerId, String newPhone) async {
  final es = await entriesOf(customerId).get();
  var batch = db.batch();
  var n = 0;
  for (final d in es.docs) {
    batch.update(d.reference, {'phone': newPhone});
    if (++n % 400 == 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  await batch.commit();
}

// ======================== حسابات العملاء (تسجيل الدخول) ========================

/// نسخة Firebase تانية عشان المدير يعمل/يعدّل حسابات من غير ما يخرج من حسابه
Future<FirebaseAuth> helperAuth() async {
  const name = 'kg-admin-helper';
  FirebaseApp app;
  try {
    app = Firebase.app(name);
  } catch (_) {
    app = await Firebase.initializeApp(name: name, options: kgFirebaseOptions);
  }
  return FirebaseAuth.instanceFor(app: app);
}

String randomPassword() => (100000 + Random.secure().nextInt(900000)).toString();

Future<String> createAccount(String phone, String name, String password) async {
  final helper = await helperAuth();
  final cred =
      await helper.createUserWithEmailAndPassword(email: phoneToEmail(phone), password: password);
  final newUid = cred.user!.uid;
  await helper.signOut();
  await db.collection('users').doc(newUid).set({
    'phone': normPhone(phone),
    'name': name,
    'password': password,
    'role': 'customer',
    'createdByAdmin': true,
    'createdAt': FieldValue.serverTimestamp(),
  });
  return newUid;
}

Future<void> changeAccountPassword(String userId, Map<String, dynamic> u, String newPass) async {
  final helper = await helperAuth();
  final cred = await helper.signInWithEmailAndPassword(
      email: phoneToEmail(u['phone'] ?? ''), password: (u['password'] ?? '').toString());
  await cred.user!.updatePassword(newPass);
  await helper.signOut();
  await db.collection('users').doc(userId).update({'password': newPass, 'disabled': false});
}

/// بيحذف الحساب نهائي لو كلمة السر متسجلة، غير كده بيوقفه
Future<bool> deleteAccount(String userId, Map<String, dynamic> u) async {
  var removed = false;
  try {
    final helper = await helperAuth();
    final cred = await helper.signInWithEmailAndPassword(
        email: phoneToEmail(u['phone'] ?? ''), password: (u['password'] ?? '').toString());
    await cred.user!.delete();
    removed = true;
  } catch (_) {}
  if (removed) {
    await db.collection('users').doc(userId).delete();
  } else {
    await db.collection('users').doc(userId).update({'disabled': true});
  }
  return removed;
}

String authError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'رقم التليفون أو كلمة السر غلط';
      case 'email-already-in-use':
        return 'الرقم ده متسجل قبل كده، ادخل بكلمة السر';
      case 'weak-password':
        return 'كلمة السر لازم تكون 6 حروف أو أرقام على الأقل';
      case 'network-request-failed':
        return 'مفيش إنترنت';
      case 'too-many-requests':
        return 'محاولات كتير، استنى شوية وجرّب تاني';
    }
    return e.message ?? e.code;
  }
  if (e is FirebaseException) {
    if (e.code == 'permission-denied') return 'مفيش صلاحية للعملية دي';
    return e.message ?? e.code;
  }
  return e.toString();
}

// ======================== الصور ========================

Future<String?> pickImageB64(BuildContext context, {double maxWidth = 700}) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.camera_alt_outlined),
          title: const Text('صوّر بالكاميرا'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('اختار من المعرض'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (src == null) return null;
  final x = await ImagePicker()
      .pickImage(source: src, maxWidth: maxWidth, maxHeight: maxWidth, imageQuality: 55);
  if (x == null) return null;
  return base64Encode(await x.readAsBytes());
}

final Map<int, Uint8List> _imgCache = {};

class B64Image extends StatelessWidget {
  final String? data;
  final double? width, height;
  final BoxFit fit;
  final IconData placeholder;
  const B64Image(this.data,
      {super.key,
      this.width,
      this.height,
      this.fit = BoxFit.cover,
      this.placeholder = Icons.spa_outlined});

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null || d.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: kBlush,
        alignment: Alignment.center,
        child: Icon(placeholder, color: kRose, size: 30),
      );
    }
    final bytes = _imgCache.putIfAbsent(Object.hash(d.length, d.hashCode), () => base64Decode(d));
    return Image.memory(bytes, width: width, height: height, fit: fit, gaplessPlayback: true);
  }
}

void showPhoto(BuildContext context, String b64) {
  showDialog(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.black,
      child: InkWell(
        onTap: () => Navigator.pop(c),
        child: InteractiveViewer(child: B64Image(b64, fit: BoxFit.contain)),
      ),
    ),
  );
}

// ======================== واجهة مشتركة ========================

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? kOwe : null));
}

Future<bool> confirm(BuildContext context, String title, String body,
    {String ok = 'تأكيد', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: kOwe) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

class EmptyView extends StatelessWidget {
  final String title;
  final String text;
  final IconData icon;
  const EmptyView(this.title, {super.key, this.text = '', this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: kRose),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
          ],
        ]),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  const StatBox(this.label, this.value,
      {super.key, this.color = kPlum, this.icon = Icons.info_outline, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 12, color: kMuted),
                      overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: color)),
            ),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(children: [
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kPlum))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

Widget orderStatusPill(String s) {
  switch (s) {
    case 'new':
      return const Pill('جديد', Colors.blue);
    case 'ready':
      return const Pill('جاهز للاستلام', Colors.orange);
    case 'delivered':
      return const Pill('اتسلّم واتسجل', kPaid);
    case 'cancelled':
      return const Pill('ملغي', Colors.grey);
  }
  return Pill(s, Colors.grey);
}

/// خانة رقمية بسيطة
TextField numField(TextEditingController c, String label,
        {ValueChanged<String>? onChanged, bool autofocus = false}) =>
    TextField(
      controller: c,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    );
