import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// كل بيانات المحل مفتوحة لايف عند المدير (محل واحد، فالحجم صغير)
class Live extends ChangeNotifier {
  static final Live I = Live._();
  Live._();

  List<Doc> customers = [];
  List<Entry> entries = [];
  List<Doc> products = [];
  List<Doc> orders = [];
  List<Doc> offers = [];
  List<Doc> users = [];
  Map<String, double> costs = {};
  List<Doc> suppliers = [];
  List<Doc> purchases = [];
  List<Doc> vouchers = [];
  List<Doc> expenses = [];
  List<Doc> damaged = [];

  double costOf(String productId) => costs[productId] ?? 0;
  StoreSettings settings = StoreSettings();
  bool ready = false;
  String error = '';
  final _subs = <StreamSubscription>[];
  final _loaded = <String>{};

  void _mark(String k) {
    _loaded.add(k);
    if (_loaded.length >= 4) ready = true;
    _byCustomer = null;
    notifyListeners();
  }

  void _err(Object e) {
    error = authError(e);
    notifyListeners();
  }

  int _users = 0;

  void start() {
    _users++;
    if (_subs.isNotEmpty) return;
    _subs.add(db.collection('customers').snapshots().listen((s) {
      customers = s.docs..sort((a, b) => toI(a.data()['code']).compareTo(toI(b.data()['code'])));
      _mark('c');
    }, onError: _err));
    _subs.add(db.collection('entries').snapshots().listen((s) {
      entries = s.docs.map((d) => Entry(d.id, d.data())).toList();
      _mark('e');
    }, onError: _err));
    _subs.add(db.collection('products').snapshots().listen((s) {
      products = s.docs
        ..sort((a, b) => (a.data()['code'] ?? '')
            .toString()
            .compareTo((b.data()['code'] ?? '').toString()));
      _mark('p');
    }, onError: _err));
    _subs.add(db.collection('orders').orderBy('createdAt', descending: true).limit(300).snapshots().listen(
        (s) {
      orders = s.docs;
      _mark('o');
    }, onError: _err));
    _subs.add(db.collection('offers').orderBy('createdAt', descending: true).snapshots().listen((s) {
      offers = s.docs;
      _mark('f');
    }, onError: _err));
    // حسابات الدخول وأسعار الشرا لصاحب المحل بس
    if (Me.owner) {
      _subs.add(db.collection('users').snapshots().listen((s) {
        users = s.docs;
        _mark('u');
      }, onError: _err));
      _subs.add(db.collection('productCosts').snapshots().listen((s) {
        costs = {for (final d in s.docs) d.id: toD(d.data()['cost'])};
        notifyListeners();
      }, onError: _err));
    }
    void sub(String name, void Function(List<Doc>) set, {String order = 'date'}) {
      _subs.add(db.collection(name).snapshots().listen((s) {
        final docs = s.docs
          ..sort((a, b) => (tsToDate(b.data()[order]) ?? DateTime(2100))
              .compareTo(tsToDate(a.data()[order]) ?? DateTime(2100)));
        set(docs);
        notifyListeners();
      }, onError: (_) {}));
    }

    if (Me.can('purchases')) {
      _subs.add(db.collection('suppliers').snapshots().listen((s) {
        suppliers = s.docs..sort((a, b) => toI(a.data()['code']).compareTo(toI(b.data()['code'])));
        notifyListeners();
      }, onError: (_) {}));
      sub('purchases', (d) => purchases = d);
      sub('vouchers', (d) => vouchers = d);
    }
    if (Me.can('expenses') || Me.can('reports')) sub('expenses', (d) => expenses = d);
    sub('damaged', (d) => damaged = d);
    _subs.add(settingsStream().listen((s) {
      settings = s;
      notifyListeners();
    }, onError: _err));
  }

  List<Doc> get customerAccounts => users.where((u) => u.data()['role'] != 'staff').toList();
  List<Doc> get staff => users.where((u) => u.data()['role'] == 'staff').toList();

  void stop() {
    _users--;
    if (_users > 0) return;
    _users = 0;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    users = [];
    costs = {};
    suppliers = [];
    purchases = [];
    vouchers = [];
    expenses = [];
    damaged = [];
    _loaded.clear();
    ready = false;
  }

  Map<String, List<Entry>>? _byCustomer;
  Map<String, List<Entry>> get byCustomer {
    final m = _byCustomer;
    if (m != null) return m;
    final out = <String, List<Entry>>{};
    for (final e in entries) {
      (out[(e.m['customerId'] ?? '').toString()] ??= []).add(e);
    }
    for (final l in out.values) {
      l.sort((a, b) => b.date.compareTo(a.date));
    }
    return _byCustomer = out;
  }

  Account accountOf(String customerId) => Account(byCustomer[customerId] ?? [], settings);

  Doc? customer(String id) {
    for (final c in customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  Doc? product(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// حساب الدخول المربوط بالعميل ده (بنفس رقم التليفون)
  Doc? userForPhone(String phone) {
    final p = normPhone(phone);
    if (p.isEmpty) return null;
    for (final u in users) {
      if (u.data()['role'] == 'staff') continue;
      if (normPhone((u.data()['phone'] ?? '').toString()) == p) return u;
    }
    return null;
  }

  Doc? customerForPhone(String phone) {
    final p = normPhone(phone);
    if (p.isEmpty) return null;
    for (final c in customers) {
      if (normPhone((c.data()['phone'] ?? '').toString()) == p) return c;
    }
    return null;
  }

  /// كل فواتير البيع (الأحدث الأول)
  List<Entry> get sales {
    final l = entries.where((e) => e.kind == 'sale' && e.debit > 0).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return l;
  }

  Doc? supplier(String id) {
    for (final c in suppliers) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// اللي عليك للمورد
  double supplierBalance(String id) {
    var b = 0.0;
    for (final p in purchases) {
      if (p.data()['supplierId'] == id) b += toD(p.data()['total']) - toD(p.data()['paid']);
    }
    for (final v in vouchers) {
      if (v.data()['partyType'] == 'supplier' && v.data()['partyId'] == id) b -= toD(v.data()['amount']);
    }
    return round2(b);
  }

  List<Doc> get lowStock => products.where((p) {
        final m = p.data();
        return m['stock'] != null && toD(m['stock']) <= toD(m['minStock'] ?? 2);
      }).toList();

  String customerName(String id) => (customer(id)?.data()['name'] ?? (id == 'cash' ? 'نقدي' : '—')).toString();

  /// أسماء الموظفين (للمندوب)
  List<String> get staffNames =>
      staff.map((u) => (u.data()['name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();

  int get newOrders => orders.where((o) => o.data()['status'] == 'new').length;
}
