import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../admin/customers.dart' show EntryCard, CodeBadge;
import '../admin/offers.dart' show offerExpired;
import '../core.dart';
import '../pdf.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

// ======================== السلة ========================

class CartLine {
  final String key;
  final String productId;
  final String name;
  final String code;
  final String? image;
  final double price;
  int qty;
  CartLine(this.key, this.productId, this.name, this.code, this.image, this.price, this.qty);
  double get total => round2(price * qty);
}

class Cart extends ChangeNotifier {
  static final Cart I = Cart._();
  Cart._();
  final Map<String, CartLine> lines = {};
  int get count => lines.values.fold(0, (a, l) => a + l.qty);
  double get total => round2(lines.values.fold(0.0, (a, l) => a + l.total));

  void add(String key, String productId, String name, String code, String? image, double price) {
    final l = lines[key];
    if (l != null) {
      l.qty++;
    } else {
      lines[key] = CartLine(key, productId, name, code, image, price, 1);
    }
    notifyListeners();
  }

  void setQty(String key, int q) {
    if (q <= 0) {
      lines.remove(key);
    } else {
      lines[key]?.qty = q;
    }
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }
}

// ======================== بيانات العميل لايف ========================

class Mine extends ChangeNotifier {
  final String phone;
  Mine(this.phone) {
    _subs.add(db.collection('offers').where('active', isEqualTo: true).snapshots().listen((s) {
      offers = s.docs.where((d) => !offerExpired(d.data())).toList()
        ..sort((a, b) => (tsToDate(b.data()['createdAt']) ?? DateTime(2000))
            .compareTo(tsToDate(a.data()['createdAt']) ?? DateTime(2000)));
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(db.collection('products').snapshots().listen((s) {
      products = s.docs.where((d) => d.data()['visible'] != false).toList()
        ..sort((a, b) => (a.data()['name'] ?? '').toString().compareTo((b.data()['name'] ?? '').toString()));
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(db.collection('customers').where('phone', isEqualTo: phone).limit(1).snapshots().listen((s) {
      ledger = s.docs.isEmpty ? null : s.docs.first;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(db.collection('entries').where('phone', isEqualTo: phone).snapshots().listen((s) {
      entries = s.docs.map((d) => Entry(d.id, d.data())).toList()..sort((a, b) => b.date.compareTo(a.date));
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(db.collection('orders').where('uid', isEqualTo: uid).snapshots().listen((s) {
      orders = s.docs
        ..sort((a, b) => (tsToDate(b.data()['createdAt']) ?? DateTime(2100))
            .compareTo(tsToDate(a.data()['createdAt']) ?? DateTime(2100)));
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(settingsStream().listen((s) {
      settings = s;
      notifyListeners();
    }, onError: (_) {}));
  }

  final _subs = <StreamSubscription>[];
  List<Doc> offers = [];
  List<Doc> products = [];
  List<Doc> orders = [];
  List<Entry> entries = [];
  Doc? ledger;
  StoreSettings settings = const StoreSettings();

  Account get account => Account(entries, settings);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

// ======================== الشاشة الرئيسية ========================

class CustomerHome extends StatefulWidget {
  final Map<String, dynamic> me;
  const CustomerHome({super.key, required this.me});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  late final Mine mine = Mine(normPhone((widget.me['phone'] ?? '').toString()));
  int tab = 0;

  @override
  void dispose() {
    mine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([mine, Cart.I]),
      builder: (context, _) {
        final pages = [
          _OffersTab(mine: mine, me: widget.me),
          _GalleryTab(mine: mine),
          _CartTab(me: widget.me, onDone: () => setState(() => tab = 3)),
          _OrdersTab(mine: mine),
          _AccountTab(mine: mine, me: widget.me),
        ];
        return Scaffold(
          body: IndexedStack(index: tab, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.local_offer_outlined), label: 'العروض'),
              const NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'المعرض'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: Cart.I.count > 0,
                  label: Text('${Cart.I.count}'),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                label: 'السلة',
              ),
              const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'طلباتي'),
              const NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي'),
            ],
          ),
        );
      },
    );
  }
}

// ======================== العروض ========================

class _OffersTab extends StatelessWidget {
  final Mine mine;
  final Map<String, dynamic> me;
  const _OffersTab({required this.mine, required this.me});

  @override
  Widget build(BuildContext context) {
    final acc = mine.account;
    return Scaffold(
      appBar: AppBar(title: const Text(kStoreName)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Card(
          color: kBlush,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('أهلاً ${me['name'] ?? ''} 🌸',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  Text(
                    acc.balance > 0.004 ? 'عليك ${money(acc.balance)}' : 'حسابك خالص',
                    style: TextStyle(color: acc.balance > 0.004 ? kOwe : kPaid),
                  ),
                ]),
              ),
              const Icon(Icons.stars_rounded, color: Colors.amber),
              const SizedBox(width: 4),
              Text('${acc.points} نقطة', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        SectionTitle('عروض النهارده (${mine.offers.length})'),
        if (mine.offers.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('مفيش عروض دلوقتي، تابعنا كل يوم 💐',
                textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
          ),
        ...mine.offers.map((o) => OfferCard(o)),
      ]),
    );
  }
}

class OfferCard extends StatelessWidget {
  final Doc o;
  const OfferCard(this.o, {super.key});
  @override
  Widget build(BuildContext context) {
    final m = o.data();
    final img = m['image']?.toString();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (img != null && img.isNotEmpty)
          InkWell(
            onTap: () => showPhoto(context, img),
            child: AspectRatio(aspectRatio: 16 / 9, child: B64Image(img)),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((m['title'] ?? '').toString(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if ((m['body'] ?? '').toString().isNotEmpty) Text(m['body'].toString()),
            const SizedBox(height: 8),
            Row(children: [
              Text(money(m['price']),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kPlum)),
              const SizedBox(width: 8),
              if (toD(m['oldPrice']) > toD(m['price']))
                Text(money(m['oldPrice']),
                    style: const TextStyle(color: kMuted, decoration: TextDecoration.lineThrough)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  Cart.I.add('offer_${o.id}', (m['productId'] ?? '').toString(),
                      '${m['title'] ?? ''} (عرض)', '', img, toD(m['price']));
                  toast(context, 'اتضاف للسلة');
                },
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('اطلب'),
              ),
            ]),
            if (m['until'] != null)
              Text('العرض لحد ${fmtDate(m['until'])}', style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ),
      ]),
    );
  }
}

// ======================== المعرض ========================

class _GalleryTab extends StatefulWidget {
  final Mine mine;
  const _GalleryTab({required this.mine});
  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<_GalleryTab> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    final list = widget.mine.products
        .where((p) => query.isEmpty || (p.data()['name'] ?? '').toString().toLowerCase().contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('المعرض')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(hintText: 'دوّر على منتج', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyView('مفيش منتجات هنا لسه', icon: Icons.storefront_outlined)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.7),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _product(context, list[i]),
                ),
        ),
      ]),
    );
  }

  Widget _product(BuildContext context, Doc p) {
    final m = p.data();
    final stock = m['stock'] == null ? null : toD(m['stock']);
    final out = stock != null && stock <= 0;
    final inCart = Cart.I.lines[p.id]?.qty ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: InkWell(
            onTap: () {
              final img = m['image']?.toString();
              if (img != null && img.isNotEmpty) showPhoto(context, img);
            },
            child: B64Image(m['image']?.toString()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((m['name'] ?? '').toString(),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(money(m['price']), style: const TextStyle(color: kPlum, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: out
                  ? const Text('خلصت', textAlign: TextAlign.center, style: TextStyle(color: kOwe))
                  : FilledButton.tonal(
                      onPressed: () => Cart.I.add(p.id, p.id, (m['name'] ?? '').toString(),
                          (m['code'] ?? '').toString(), m['image']?.toString(), toD(m['price'])),
                      child: Text(inCart > 0 ? 'في السلة ($inCart) +' : 'أضف للسلة'),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ======================== السلة ========================

class _CartTab extends StatefulWidget {
  final Map<String, dynamic> me;
  final VoidCallback onDone;
  const _CartTab({required this.me, required this.onDone});
  @override
  State<_CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<_CartTab> {
  final note = TextEditingController();
  bool busy = false;

  Future<void> _order() async {
    final cart = Cart.I;
    if (cart.lines.isEmpty) return;
    setState(() => busy = true);
    try {
      await db.collection('orders').add({
        'uid': uid,
        'phone': normPhone((widget.me['phone'] ?? '').toString()),
        'name': (widget.me['name'] ?? '').toString(),
        'items': cart.lines.values
            .map((l) => {
                  'productId': l.productId,
                  'name': l.name,
                  'code': l.code,
                  'qty': l.qty,
                  'price': l.price,
                })
            .toList(),
        'total': cart.total,
        'note': note.text.trim(),
        'status': 'new',
        'createdAt': FieldValue.serverTimestamp(),
      });
      cart.clear();
      note.clear();
      if (!mounted) return;
      toast(context, 'طلبك وصل للمحل 💐');
      widget.onDone();
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cart = Cart.I;
    return Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: cart.lines.isEmpty
          ? const EmptyView('السلة فاضية', text: 'اختار من العروض أو المعرض.', icon: Icons.shopping_cart_outlined)
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              ...cart.lines.values.map((l) => Card(
                    child: ListTile(
                      leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8), child: B64Image(l.image, width: 48, height: 48)),
                      title: Text(l.name),
                      subtitle: Text('${money(l.price)} × ${l.qty} = ${money(l.total)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => cart.setQty(l.key, l.qty - 1)),
                        Text('${l.qty}'),
                        IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: kPlum),
                            onPressed: () => cart.setQty(l.key, l.qty + 1)),
                      ]),
                    ),
                  )),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'ملاحظة للمحل (اختياري)'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  Text(money(cart.total),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kPlum)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: busy ? null : _order,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('ابعت الطلب'),
                ),
              ),
            ]),
    );
  }
}

// ======================== طلباتي ========================

class _OrdersTab extends StatelessWidget {
  final Mine mine;
  const _OrdersTab({required this.mine});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: mine.orders.isEmpty
          ? const EmptyView('مفيش طلبات لسه', icon: Icons.receipt_long_outlined)
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: mine.orders.map((o) {
                final m = o.data();
                final items = ((m['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map));
                final status = (m['status'] ?? 'new').toString();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                            child: Text(fmtDate(m['createdAt'], time: true),
                                style: const TextStyle(color: kMuted, fontSize: 12))),
                        orderStatusPill(status),
                      ]),
                      const SizedBox(height: 6),
                      ...items.map((it) => Text('${it['name']}  ×${num2(it['qty'])}')),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text(money(m['total']), style: const TextStyle(fontWeight: FontWeight.bold, color: kPlum)),
                        const Spacer(),
                        if (status == 'new')
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: kOwe),
                            onPressed: () async {
                              if (await confirm(context, 'إلغاء الطلب؟', 'متأكد إنك عاوز تلغي الطلب؟',
                                  ok: 'إلغاء الطلب', danger: true)) {
                                await db.collection('orders').doc(o.id).update({'status': 'cancelled'});
                              }
                            },
                            child: const Text('إلغاء'),
                          ),
                      ]),
                    ]),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ======================== حسابي ========================

class _AccountTab extends StatelessWidget {
  final Mine mine;
  final Map<String, dynamic> me;
  const _AccountTab({required this.mine, required this.me});

  @override
  Widget build(BuildContext context) {
    final acc = mine.account;
    final ledger = mine.ledger?.data();
    final customer = ledger ?? {'name': me['name'], 'phone': me['phone'], 'code': 0};
    return Scaffold(
      appBar: AppBar(title: const Text('حسابي'), actions: [
        IconButton(
          tooltip: 'خروج',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            if (await confirm(context, 'خروج', 'تخرج من حسابك؟', ok: 'خروج')) {
              Cart.I.clear();
              await auth.signOut();
            }
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text((me['name'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                if (ledger != null) CodeBadge(ledger['code']),
              ]),
              Text((me['phone'] ?? '').toString(),
                  textDirection: TextDirection.ltr, style: const TextStyle(color: kMuted)),
              const SizedBox(height: 12),
              Row(children: [
                _box('اشتريت بـ', acc.debit, kOwe),
                const SizedBox(width: 8),
                _box('دفعت', acc.paid, kPaid),
                const SizedBox(width: 8),
                _box(acc.balance >= 0 ? 'الباقي عليك' : 'ليك رصيد', acc.balance.abs(),
                    acc.balance > 0.004 ? kOwe : kPaid),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.stars_rounded, color: Colors.amber),
                const SizedBox(width: 4),
                Text('${acc.points} نقطة', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              Text(mine.settings.rulesText, style: const TextStyle(fontSize: 12, color: kMuted)),
              if (acc.entries.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => shareStatementPdf(context, customer, acc),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('كشف حسابي PDF'),
                ),
              ],
            ]),
          ),
        ),
        SectionTitle('فواتيري وحركاتي (${acc.entries.length})'),
        if (acc.entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('لسه مفيش حركات على حسابك.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
          ),
        ...acc.entries.map((e) => EntryCard(e, admin: false, customer: customer, account: acc)),
      ]),
    );
  }

  Widget _box(String label, double v, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFF6EFF1), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
            FittedBox(
                child: Text(num2(v), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: color))),
          ]),
        ),
      );
}
