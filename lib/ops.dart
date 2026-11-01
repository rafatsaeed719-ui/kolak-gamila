import 'package:cloud_firestore/cloud_firestore.dart';

import 'core.dart';

/// عدّاد بيزيد (رقم الفاتورة، السند، ...)
Future<int> nextNo(String field) => nextCounter(field);

/// سطر في فاتورة بيع
class SaleLine {
  String productId;
  String name;
  String code;
  double qty;
  double price;
  double paid;
  double returned;
  SaleLine({
    this.productId = '',
    required this.name,
    this.code = '',
    this.qty = 1,
    this.price = 0,
    this.paid = 0,
    this.returned = 0,
  });

  double get total => round2(qty * price);

  factory SaleLine.fromMap(Map<String, dynamic> m) => SaleLine(
        productId: (m['productId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        code: (m['code'] ?? '').toString(),
        qty: toD(m['qty']),
        price: toD(m['price']),
        paid: toD(m['paid']),
        returned: toD(m['returned']),
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'code': code,
        'qty': qty,
        'price': price,
        'paid': round2(paid),
        if (returned > 0) 'returned': returned,
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

/// العميل النقدي (للبيع من غير عميل)
const String kCashId = 'cash';

Future<void> ensureCashCustomer() async {
  final ref = db.collection('customers').doc(kCashId);
  final s = await ref.get();
  if (!s.exists) {
    await ref.set({
      'code': 0,
      'name': 'نقدي',
      'phone': '',
      'address': '',
      'notes': 'البيع الكاش من غير عميل',
      'cash': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// حفظ بيع/مديونية جديدة أو تعديل واحدة قديمة.
/// الخصم بيتحسب على الأصناف الأول، وبعده الدفعة اللي مع البيع، والباقي على المديونية اليدوي.
Future<String> saveSale({
  required String customerId,
  required String phone,
  required List<SaleLine> lines,
  required double extra,
  required double paid,
  required String note,
  required List<String> photos,
  required DateTime date,
  double discount = 0,
  String payMethod = 'cash',
  String rep = '',
  Entry? old,
  String? orderId,
}) async {
  final clean = lines.where((l) => l.name.trim().isNotEmpty && l.qty > 0).toList();
  // اللي اتدفع على الفاتورة دي من دفعات تانية (بعد كده)
  var external = 0.0;
  if (old != null) {
    final oldLines = old.items.map(SaleLine.fromMap).toList();
    external = oldLines.fold(0.0, (a, l) => a + l.paid) +
        toD(old.m['extraPaid']) -
        old.discount -
        toD(old.m['ownPaid']);
    if (external < 0) external = 0;
  }
  // الكميات المرتجعة بتفضل زي ما هي
  final oldReturned = <String, double>{};
  if (old != null) {
    for (final it in old.items) {
      final r = toD(it['returned']);
      if (r > 0) oldReturned['${it['productId']}|${it['name']}'] = r;
    }
  }
  for (final l in clean) {
    l.paid = 0;
  }
  var extraPaid = 0.0;
  void apply(double amount) {
    final left = _fill(clean, amount);
    if (left > 0.004) {
      final room = extra - extraPaid;
      final t = left < room ? left : room;
      if (t > 0) extraPaid = round2(extraPaid + t);
    }
  }

  apply(discount);
  apply(external);
  final before = clean.fold(0.0, (a, l) => a + l.paid) + extraPaid;
  apply(paid);
  final ownPaid = round2(clean.fold(0.0, (a, l) => a + l.paid) + extraPaid - before);

  final gross = round2(clean.fold(0.0, (a, l) => a + l.total) + extra);
  final debit = round2(gross - discount);
  final ref = old == null ? db.collection('entries').doc() : db.collection('entries').doc(old.id);
  var invoiceNo = old?.invoiceNo ?? 0;
  if (invoiceNo == 0 && debit > 0) invoiceNo = await nextCounter('invoice');

  final batch = db.batch();
  batch.set(ref, {
    'customerId': customerId,
    'phone': normPhone(phone),
    'kind': 'sale',
    'date': Timestamp.fromDate(date),
    'items': clean.map((l) {
      final m = l.toMap();
      final r = oldReturned['${l.productId}|${l.name}'];
      if (r != null) m['returned'] = r;
      return m;
    }).toList(),
    'extra': round2(extra),
    'extraPaid': extraPaid,
    'discount': round2(discount),
    'gross': gross,
    'debit': debit,
    'credit': round2(paid),
    'ownPaid': ownPaid,
    'payMethod': payMethod,
    'rep': rep,
    'note': note,
    'photos': photos,
    'invoiceNo': invoiceNo,
    if (orderId != null) 'orderId': orderId,
    if (old != null && old.m['orderId'] != null) 'orderId': old.m['orderId'],
    'createdAt': old?.m['createdAt'] ?? FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'by': old?.by.isNotEmpty == true ? old!.by : Me.name,
  });
  // المخزن: نرجّع الكميات القديمة ونخصم الجديدة (من غير المرتجع)
  final delta = <String, double>{};
  if (old != null) {
    for (final it in old.items) {
      final pid = (it['productId'] ?? '').toString();
      if (pid.isNotEmpty) delta[pid] = (delta[pid] ?? 0) + toD(it['qty']) - toD(it['returned']);
    }
  }
  for (final l in clean) {
    if (l.productId.isNotEmpty) {
      final r = oldReturned['${l.productId}|${l.name}'] ?? 0;
      delta[l.productId] = (delta[l.productId] ?? 0) - (l.qty - r);
    }
  }
  await _applyStock(batch, delta);
  await batch.commit();
  return ref.id;
}

/// دفعة: [chosen] الأصناف اللي العميل دافع تمنها بالترتيب، والباقي بيتوزع على الأقدم.
/// [onlySale] لو الدفعة على فاتورة واحدة بالذات.
Future<void> savePayment({
  required String customerId,
  required String phone,
  required Account account,
  required double amount,
  required List<OpenItem> chosen,
  required String note,
  required DateTime date,
  String method = 'cash',
  String? onlySale,
}) async {
  final saleLines = <String, List<SaleLine>>{};
  final extraPaid = <String, double>{};
  final sales = account.entries.where((e) => e.kind == 'sale').toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  for (final e in sales) {
    saleLines[e.id] = e.items.map(SaleLine.fromMap).toList();
    extraPaid[e.id] = toD(e.m['extraPaid']);
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

  void takeExtra(Entry e) {
    if (left <= 0.004) return;
    final rem = round2(e.extra - (extraPaid[e.id] ?? 0));
    if (rem <= 0.004) return;
    final t = rem < left ? rem : left;
    extraPaid[e.id] = round2((extraPaid[e.id] ?? 0) + t);
    left = round2(left - t);
    allocs.add({'entryId': e.id, 'idx': -1, 'amount': t, 'name': 'مديونية'});
  }

  for (final o in chosen) {
    take(o.sale.id, o.index);
  }
  for (final e in sales) {
    if (onlySale != null && e.id != onlySale) continue;
    for (var i = 0; i < saleLines[e.id]!.length; i++) {
      take(e.id, i);
    }
    takeExtra(e);
  }
  if (onlySale != null) {
    // الزيادة (لو فيه) على باقي الفواتير
    for (final e in sales) {
      for (var i = 0; i < saleLines[e.id]!.length; i++) {
        take(e.id, i);
      }
      takeExtra(e);
    }
  }

  final batch = db.batch();
  final touched = allocs.map((a) => a['entryId'] as String).toSet();
  for (final id in touched) {
    batch.update(db.collection('entries').doc(id), {
      'items': saleLines[id]!.map((l) => l.toMap()).toList(),
      'extraPaid': extraPaid[id] ?? 0,
    });
  }
  final no = await nextCounter('receipt');
  batch.set(db.collection('entries').doc(), {
    'customerId': customerId,
    'phone': normPhone(phone),
    'kind': 'pay',
    'date': Timestamp.fromDate(date),
    'debit': 0,
    'credit': round2(amount),
    'method': method,
    'receiptNo': no,
    'allocations': allocs,
    'chosen': chosen.isNotEmpty,
    'note': note,
    'photos': <String>[],
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'by': Me.name,
  });
  await batch.commit();
}

/// مرتجع من فاتورة: [qtys] الكمية المرتجعة لكل سطر (بالترتيب)
Future<void> saveReturn({
  required Entry sale,
  required Map<int, double> qtys,
  required String note,
}) async {
  final lines = sale.items;
  final allocs = <Map<String, dynamic>>[];
  final retItems = <Map<String, dynamic>>[];
  var value = 0.0;
  final delta = <String, double>{};
  for (final e in qtys.entries) {
    final i = e.key;
    final q = e.value;
    if (q <= 0 || i >= lines.length) continue;
    final it = lines[i];
    final price = toD(it['price']);
    final v = round2(q * price);
    value += v;
    it['returned'] = toD(it['returned']) + q;
    // المرتجع بيقفل الجزء اللي لسه عليه فلوس من الصنف ده
    final total = toD(it['qty']) * price;
    final rem = round2(total - toD(it['paid']));
    final t = rem <= 0 ? 0.0 : (v < rem ? v : rem);
    if (t > 0) {
      it['paid'] = round2(toD(it['paid']) + t);
      allocs.add({'entryId': sale.id, 'idx': i, 'amount': t, 'name': it['name']});
    }
    retItems.add({'idx': i, 'name': it['name'], 'productId': it['productId'] ?? '', 'qty': q, 'price': price});
    final pid = (it['productId'] ?? '').toString();
    if (pid.isNotEmpty) delta[pid] = (delta[pid] ?? 0) + q;
  }
  if (value <= 0) return;
  final batch = db.batch();
  batch.update(db.collection('entries').doc(sale.id), {'items': lines});
  batch.set(db.collection('entries').doc(), {
    'customerId': sale.m['customerId'],
    'phone': sale.m['phone'] ?? '',
    'kind': 'return',
    'saleId': sale.id,
    'invoiceNo': 0,
    'saleNo': sale.invoiceNo,
    'date': Timestamp.now(),
    'debit': 0,
    'credit': round2(value),
    'items': retItems,
    'allocations': allocs,
    'note': note,
    'photos': <String>[],
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'by': Me.name,
  });
  await _applyStock(batch, delta);
  await batch.commit();
}

/// حذف حركة: البيع بيرجّع المخزن، والدفعة/المرتجع بيرجّعوا الأصناف زي ما كانت
Future<void> deleteEntry(Entry e, Account account) async {
  final batch = db.batch();
  if (e.kind == 'sale') {
    final delta = <String, double>{};
    for (final it in e.items) {
      final pid = (it['productId'] ?? '').toString();
      if (pid.isNotEmpty) delta[pid] = (delta[pid] ?? 0) + toD(it['qty']) - toD(it['returned']);
    }
    await _applyStock(batch, delta);
  }
  if (e.kind == 'pay' || e.kind == 'return') {
    final byId = {for (final x in account.entries) x.id: x};
    final changed = <String, List<Map<String, dynamic>>>{};
    final extraPaid = <String, double>{};
    for (final a in e.allocations) {
      final id = (a['entryId'] ?? '').toString();
      final sale = byId[id];
      if (sale == null) continue;
      final lines = changed[id] ??= sale.items;
      extraPaid[id] ??= toD(sale.m['extraPaid']);
      final i = toI(a['idx']);
      if (i < 0) {
        final v = extraPaid[id]! - toD(a['amount']);
        extraPaid[id] = round2(v < 0 ? 0 : v);
      } else if (i < lines.length) {
        final v = toD(lines[i]['paid']) - toD(a['amount']);
        lines[i]['paid'] = round2(v < 0 ? 0 : v);
      }
    }
    if (e.kind == 'return') {
      final sale = byId[(e.m['saleId'] ?? '').toString()];
      if (sale != null) {
        final lines = changed[sale.id] ??= sale.items;
        extraPaid[sale.id] ??= toD(sale.m['extraPaid']);
        final delta = <String, double>{};
        for (final r in e.items) {
          final i = toI(r['idx']);
          if (i < lines.length) {
            final v = toD(lines[i]['returned']) - toD(r['qty']);
            lines[i]['returned'] = v < 0 ? 0 : v;
          }
          final pid = (r['productId'] ?? '').toString();
          if (pid.isNotEmpty) delta[pid] = (delta[pid] ?? 0) - toD(r['qty']);
        }
        await _applyStock(batch, delta);
      }
    }
    changed.forEach((id, lines) {
      batch.update(db.collection('entries').doc(id), {'items': lines, 'extraPaid': extraPaid[id] ?? 0});
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
    'by': Me.name,
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
    'by': Me.name,
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
    photos: [],
    date: DateTime.now(),
    orderId: orderId,
    rep: Me.owner ? '' : Me.name,
  );
  await db.collection('orders').doc(orderId).update({
    'status': 'delivered',
    'entryId': id,
    'customerId': cust.id,
    'deliveredAt': FieldValue.serverTimestamp(),
  });
  return id;
}


// ======================== المخزن: هالك ========================

Future<void> saveDamaged({
  required String productId,
  required String name,
  required double qty,
  required double cost,
  required String reason,
}) async {
  final batch = db.batch();
  batch.set(db.collection('damaged').doc(), {
    'productId': productId,
    'name': name,
    'qty': qty,
    'cost': cost,
    'value': round2(qty * cost),
    'reason': reason,
    'date': Timestamp.now(),
    'by': Me.name,
  });
  await _applyStock(batch, {productId: -qty});
  await batch.commit();
}

Future<void> deleteDamaged(String id, Map<String, dynamic> m) async {
  final batch = db.batch();
  batch.delete(db.collection('damaged').doc(id));
  await _applyStock(batch, {(m['productId'] ?? '').toString(): toD(m['qty'])});
  await batch.commit();
}

// ======================== المشتريات ========================

class PurchaseLine {
  String productId;
  String name;
  double qty;
  double cost;
  PurchaseLine({this.productId = '', required this.name, this.qty = 1, this.cost = 0});
  double get total => round2(qty * cost);
  Map<String, dynamic> toMap() => {'productId': productId, 'name': name, 'qty': qty, 'cost': cost};
  factory PurchaseLine.fromMap(Map<String, dynamic> m) => PurchaseLine(
      productId: (m['productId'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      qty: toD(m['qty']),
      cost: toD(m['cost']));
}

Future<void> savePurchase({
  required String supplierId,
  required String supplierName,
  required List<PurchaseLine> lines,
  required double discount,
  required double paid,
  required String method,
  required String note,
  required DateTime date,
  String? oldId,
  Map<String, dynamic>? old,
}) async {
  final clean = lines.where((l) => l.name.trim().isNotEmpty && l.qty > 0).toList();
  final gross = round2(clean.fold(0.0, (a, l) => a + l.total));
  final total = round2(gross - discount);
  final ref = oldId == null ? db.collection('purchases').doc() : db.collection('purchases').doc(oldId);
  final no = old == null ? await nextCounter('purchase') : toI(old['no']);
  final batch = db.batch();
  batch.set(ref, {
    'no': no,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'items': clean.map((l) => l.toMap()).toList(),
    'gross': gross,
    'discount': round2(discount),
    'total': total,
    'paid': round2(paid),
    'method': method,
    'note': note,
    'date': Timestamp.fromDate(date),
    'by': Me.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  final delta = <String, double>{};
  if (old != null) {
    for (final it in ((old['items'] as List?) ?? [])) {
      final m = Map<String, dynamic>.from(it as Map);
      final pid = (m['productId'] ?? '').toString();
      if (pid.isNotEmpty) delta[pid] = (delta[pid] ?? 0) - toD(m['qty']);
    }
  }
  for (final l in clean) {
    if (l.productId.isEmpty) continue;
    delta[l.productId] = (delta[l.productId] ?? 0) + l.qty;
    // آخر سعر شرا
    if (l.cost > 0) {
      batch.set(db.collection('productCosts').doc(l.productId), {'cost': l.cost});
    }
  }
  // المشتريات بتبدأ تتبع المخزن حتى لو الصنف ملوش كمية
  for (final e in delta.entries) {
    if (e.value.abs() < 0.0001) continue;
    final pref = db.collection('products').doc(e.key);
    final snap = await pref.get();
    if (!snap.exists) continue;
    if (snap.data()?['stock'] == null) {
      batch.update(pref, {'stock': e.value});
    } else {
      batch.update(pref, {'stock': FieldValue.increment(e.value)});
    }
  }
  await batch.commit();
}

Future<void> deletePurchase(String id, Map<String, dynamic> m) async {
  final batch = db.batch();
  final delta = <String, double>{};
  for (final it in ((m['items'] as List?) ?? [])) {
    final x = Map<String, dynamic>.from(it as Map);
    final pid = (x['productId'] ?? '').toString();
    if (pid.isNotEmpty) delta[pid] = (delta[pid] ?? 0) - toD(x['qty']);
  }
  await _applyStock(batch, delta);
  batch.delete(db.collection('purchases').doc(id));
  await batch.commit();
}

// ======================== سندات الصرف والمصروفات ========================

Future<void> saveVoucher({
  required String partyType, // supplier / other
  required String partyId,
  required String partyName,
  required double amount,
  required String method,
  required String note,
  required DateTime date,
}) async {
  final no = await nextCounter('voucher');
  await db.collection('vouchers').add({
    'no': no,
    'type': 'out',
    'partyType': partyType,
    'partyId': partyId,
    'partyName': partyName,
    'amount': round2(amount),
    'method': method,
    'note': note,
    'date': Timestamp.fromDate(date),
    'by': Me.name,
  });
}

Future<void> saveExpense({
  String? id,
  required String category,
  required double amount,
  required String method,
  required String note,
  required DateTime date,
}) async {
  final ref = id == null ? db.collection('expenses').doc() : db.collection('expenses').doc(id);
  await ref.set({
    'category': category,
    'amount': round2(amount),
    'method': method,
    'note': note,
    'date': Timestamp.fromDate(date),
    'by': Me.name,
  });
}
