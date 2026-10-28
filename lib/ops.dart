import 'package:cloud_firestore/cloud_firestore.dart';

import 'core.dart';

/// سطر في فاتورة بيع
class SaleLine {
  String productId;
  String name;
  String code;
  double qty;
  double price;
  double paid;
  SaleLine({
    this.productId = '',
    required this.name,
    this.code = '',
    this.qty = 1,
    this.price = 0,
    this.paid = 0,
  });

  double get total => round2(qty * price);

  factory SaleLine.fromMap(Map<String, dynamic> m) => SaleLine(
        productId: (m['productId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        code: (m['code'] ?? '').toString(),
        qty: toD(m['qty']),
        price: toD(m['price']),
        paid: toD(m['paid']),
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'code': code,
        'qty': qty,
        'price': price,
        'paid': round2(paid),
      };
}

/// تحديث المخزن للأصناف اللي متتبع مخزنها بس (المنتج موجود وليه كمية)
Future<void> _applyStock(WriteBatch batch, Map<String, double> delta) async {
  for (final entry in delta.entries) {
    if (entry.value.abs() < 0.0001) continue;
    final ref = db.collection('products').doc(entry.key);
    final snap = await ref.get();
    if (!snap.exists || snap.data()?['stock'] == null) continue;
    batch.update(ref, {'stock': FieldValue.increment(entry.value)});
  }
}

/// يوزّع مبلغ على أسطر بالترتيب لحد ما يخلص
double _fill(List<SaleLine> lines, double amount) {
  var left = amount;
  for (final l in lines) {
    if (left <= 0.004) break;
    final rem = l.total - l.paid;
    if (rem <= 0.004) continue;
    final take = rem < left ? rem : left;
    l.paid = round2(l.paid + take);
    left = round2(left - take);
  }
  return left;
}

/// حفظ بيع/مديونية جديدة أو تعديل واحدة قديمة.
/// الدفعة اللي مع البيع بتتحسب على أصناف نفس الفاتورة الأول.
Future<String> saveSale({
  required String customerId,
  required String phone,
  required List<SaleLine> lines,
  required double extra,
  required double paid,
  required String note,
  required List<String> photos,
  required DateTime date,
  Entry? old,
  String? orderId,
}) async {
  final clean = lines.where((l) => l.name.trim().isNotEmpty && l.qty > 0).toList();
  // الدفعات اللي اتسجلت على الأصناف دي من فواتير تانية (من غير دفعة الفاتورة نفسها)
  if (old != null) {
    final oldLines = old.items.map(SaleLine.fromMap).toList();
    final oldOwn = toD(old.m['ownPaid']);
    // اللي اتدفع من برّه = إجمالي المدفوع على الأسطر - المدفوع مع الفاتورة نفسها
    final external = oldLines.fold(0.0, (a, l) => a + l.paid) - oldOwn;
    for (final l in clean) {
      l.paid = 0;
    }
    if (external > 0) _fill(clean, external);
  } else {
    for (final l in clean) {
      l.paid = 0;
    }
  }
  final before = clean.fold(0.0, (a, l) => a + l.paid);
  _fill(clean, paid);
  final ownPaid = round2(clean.fold(0.0, (a, l) => a + l.paid) - before);

  final debit = round2(clean.fold(0.0, (a, l) => a + l.total) + extra);
  final ref = old == null ? db.collection('entries').doc() : db.collection('entries').doc(old.id);
  var invoiceNo = old?.invoiceNo ?? 0;
  if (invoiceNo == 0 && debit > 0) invoiceNo = await nextCounter('invoice');

  final batch = db.batch();
  batch.set(ref, {
    'customerId': customerId,
    'phone': normPhone(phone),
    'kind': 'sale',
    'date': Timestamp.fromDate(date),
    'items': clean.map((l) => l.toMap()).toList(),
    'extra': round2(extra),
    'debit': debit,
    'credit': round2(paid),
    'ownPaid': ownPaid,
    'note': note,
    'photos': photos,
    'invoiceNo': invoiceNo,
    if (orderId != null) 'orderId': orderId,
    if (old != null && old.m['orderId'] != null) 'orderId': old.m['orderId'],
    'updatedAt': FieldValue.serverTimestamp(),
  });
  // المخزن: نرجّع الكميات القديمة ونخصم الجديدة
  final delta = <String, double>{};
  if (old != null) {
    for (final it in old.items) {
      final pid = (it['productId'] ?? '').toString();
      if (pid.isNotEmpty) delta[pid] = (delta[pid] ?? 0) + toD(it['qty']);
    }
  }
  for (final l in clean) {
    if (l.productId.isNotEmpty) delta[l.productId] = (delta[l.productId] ?? 0) - l.qty;
  }
  await _applyStock(batch, delta);
  await batch.commit();
  return ref.id;
}

/// دفعة: [chosen] الأصناف اللي العميل دافع تمنها بالترتيب، والباقي (لو فيه) بيتوزع على الأقدم.
Future<void> savePayment({
  required String customerId,
  required String phone,
  required Account account,
  required double amount,
  required List<OpenItem> chosen,
  required String note,
  required DateTime date,
}) async {
  // نسخة من أسطر كل فاتورة مفتوحة
  final saleLines = <String, List<SaleLine>>{};
  final sales = <String, Entry>{};
  for (final e in account.entries.where((e) => e.kind == 'sale')) {
    saleLines[e.id] = e.items.map(SaleLine.fromMap).toList();
    sales[e.id] = e;
  }
  final allocs = <Map<String, dynamic>>[];
  var left = round2(amount);

  void take(String saleId, int idx) {
    if (left <= 0.004) return;
    final l = saleLines[saleId]![idx];
    final rem = round2(l.total - l.paid);
    if (rem <= 0.004) return;
    final t = rem < left ? rem : left;
    l.paid = round2(l.paid + t);
    left = round2(left - t);
    allocs.add({'entryId': saleId, 'idx': idx, 'amount': t, 'name': l.name});
  }

  for (final o in chosen) {
    take(o.sale.id, o.index);
  }
  for (final o in account.openItems) {
    take(o.sale.id, o.index);
  }

  final batch = db.batch();
  final touched = allocs.map((a) => a['entryId'] as String).toSet();
  for (final id in touched) {
    batch.update(db.collection('entries').doc(id),
        {'items': saleLines[id]!.map((l) => l.toMap()).toList()});
  }
  batch.set(db.collection('entries').doc(), {
    'customerId': customerId,
    'phone': normPhone(phone),
    'kind': 'pay',
    'date': Timestamp.fromDate(date),
    'debit': 0,
    'credit': round2(amount),
    'allocations': allocs,
    'chosen': chosen.isNotEmpty,
    'note': note,
    'photos': <String>[],
    'updatedAt': FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

/// حذف حركة: البيع بيرجّع المخزن، والدفعة بترجّع الأصناف اللي كانت دافعة تمنها
Future<void> deleteEntry(Entry e, Account account) async {
  final batch = db.batch();
  if (e.kind == 'sale') {
    final delta = <String, double>{};
    for (final it in e.items) {
      final pid = (it['productId'] ?? '').toString();
      if (pid.isNotEmpty) delta[pid] = (delta[pid] ?? 0) + toD(it['qty']);
    }
    await _applyStock(batch, delta);
  }
  if (e.kind == 'pay') {
    final byId = {for (final x in account.entries) x.id: x};
    final changed = <String, List<SaleLine>>{};
    for (final a in e.allocations) {
      final id = (a['entryId'] ?? '').toString();
      final sale = byId[id];
      if (sale == null) continue;
      final lines = changed[id] ??= sale.items.map(SaleLine.fromMap).toList();
      final i = toI(a['idx']);
      if (i < lines.length) {
        final v = lines[i].paid - toD(a['amount']);
        lines[i].paid = round2(v < 0 ? 0 : v);
      }
    }
    changed.forEach((id, lines) {
      batch.update(db.collection('entries').doc(id), {'items': lines.map((l) => l.toMap()).toList()});
    });
  }
  batch.delete(db.collection('entries').doc(e.id));
  await batch.commit();
}

Future<void> saveAdjust({
  required String customerId,
  required String phone,
  required double delta,
  required String note,
  required DateTime date,
  Entry? old,
}) async {
  final ref = old == null ? db.collection('entries').doc() : db.collection('entries').doc(old.id);
  await ref.set({
    'customerId': customerId,
    'phone': normPhone(phone),
    'kind': 'adjust',
    'date': Timestamp.fromDate(date),
    'debit': delta > 0 ? round2(delta) : 0,
    'credit': delta < 0 ? round2(-delta) : 0,
    'note': note,
    'photos': <String>[],
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> saveRedeem({
  required String customerId,
  required String phone,
  required int points,
  required double value,
  required String note,
}) async {
  await db.collection('entries').add({
    'customerId': customerId,
    'phone': normPhone(phone),
    'kind': 'redeem',
    'date': Timestamp.now(),
    'points': points,
    'debit': 0,
    'credit': round2(value),
    'note': note,
    'photos': <String>[],
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

/// الطلب اتسلّم: بيتسجل بيع على حساب العميل اللي ليه نفس الرقم (أو بيتعمله حساب في الدفتر)
Future<String> deliverOrder(String orderId, Map<String, dynamic> o, {double paid = 0}) async {
  final cust = await customerForPhone((o['phone'] ?? '').toString(), (o['name'] ?? '').toString());
  final items = ((o['items'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .map((m) => SaleLine(
            productId: (m['productId'] ?? '').toString(),
            name: (m['name'] ?? '').toString(),
            code: (m['code'] ?? '').toString(),
            qty: toD(m['qty']),
            price: toD(m['price']),
          ))
      .toList();
  final id = await saveSale(
    customerId: cust.id,
    phone: (o['phone'] ?? '').toString(),
    lines: items,
    extra: 0,
    paid: paid,
    note: 'طلب من التطبيق${(o['note'] ?? '').toString().isEmpty ? '' : ' — ${o['note']}'}',
    photos: const [],
    date: DateTime.now(),
    orderId: orderId,
  );
  await db.collection('orders').doc(orderId).update({
    'status': 'delivered',
    'entryId': id,
    'customerId': cust.id,
    'deliveredAt': FieldValue.serverTimestamp(),
  });
  return id;
}
