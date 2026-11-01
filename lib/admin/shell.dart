import 'package:flutter/material.dart';

import '../core.dart';
import 'accounts.dart';
import 'admin_home.dart';
import 'customers.dart';
import 'inventory.dart';
import 'invoice_view.dart';
import 'live.dart';
import 'money_screens.dart';
import 'offers.dart';
import 'orders.dart';
import 'products.dart';
import 'reports.dart';
import 'sale_screen.dart';
import 'sales_log.dart';
import 'settings_screen.dart';
import 'staff.dart';
import 'tools.dart';

/// صفحة في القايمة الجانبية
class NavItem {
  final String key;
  final String label;
  final IconData icon;
  final String section;
  final bool visible;
  final Widget Function() build;
  const NavItem(this.key, this.label, this.icon, this.section, this.visible, this.build);
}

/// عشان أي صفحة جوه البرنامج تقدر تفتح القايمة أو تروح لصفحة تانية
class ShellScope extends InheritedWidget {
  final bool wide;
  final VoidCallback openMenu;
  final ValueChanged<String> go;
  const ShellScope({super.key, required this.wide, required this.openMenu, required this.go, required super.child});

  static ShellScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => old.wide != wide;
}

/// شريط العنوان لكل صفحة: زرار القايمة على الموبايل وزرار البحث
PreferredSizeWidget pageAppBar(BuildContext context, String title,
    {List<Widget> actions = const [], PreferredSizeWidget? bottom}) {
  final shell = ShellScope.maybeOf(context);
  final narrow = shell != null && !shell.wide;
  return AppBar(
    title: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
    centerTitle: false,
    leading: narrow ? IconButton(icon: Icon(Icons.menu), onPressed: shell.openMenu) : null,
    automaticallyImplyLeading: shell == null,
    actions: [
      ...actions,
      if (narrow)
        IconButton(
          tooltip: 'بحث',
          icon: Icon(Icons.search),
          onPressed: () => openGlobalSearch(context),
        ),
      SizedBox(width: 4),
    ],
    bottom: bottom,
  );
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  String tab = '';
  final visited = <String>{};
  int saleKey = 0;

  @override
  void initState() {
    super.initState();
    Live.I.start();
    AppLock.lockOnOpenIfNeeded();
  }

  @override
  void dispose() {
    Live.I.stop();
    super.dispose();
  }

  List<NavItem> get items => [
        NavItem('home', 'لوحة التحكم', Icons.space_dashboard_outlined, 'الرئيسية', Me.can('reports'),
            () => Dashboard(onGo: _go)),
        NavItem('sale', 'فاتورة بيع', Icons.receipt_long_outlined, 'العمليات', Me.can('sell'),
            () => SaleScreen(key: ValueKey('sale$saleKey'), embedded: true, onSaved: () => setState(() => saleKey++))),
        NavItem('sales', 'سجل المبيعات', Icons.history, 'العمليات', true, () => SalesLog()),
        NavItem('orders', 'طلبات العملاء', Icons.shopping_bag_outlined, 'العمليات', Me.can('orders'),
            () => OrdersScreen()),
        NavItem('purchases', 'المشتريات', Icons.shopping_cart_outlined, 'العمليات', Me.can('purchases'),
            () => PurchasesScreen()),
        NavItem('vouchers', 'سندات التحصيل والصرف', Icons.request_quote_outlined, 'العمليات',
            Me.can('sell') || Me.can('purchases'), () => VouchersScreen()),
        NavItem('expenses', 'المصروفات', Icons.account_balance_wallet_outlined, 'العمليات', Me.can('expenses'),
            () => ExpensesScreen()),
        NavItem('products', 'الأصناف والمخزون', Icons.inventory_2_outlined, 'البيانات', true,
            () => ProductsScreen()),
        NavItem('low', 'المخزون الحرج', Icons.warning_amber_rounded, 'البيانات', true, () => LowStockScreen()),
        NavItem('damaged', 'هالك', Icons.broken_image_outlined, 'البيانات', Me.can('products'),
            () => DamagedScreen()),
        NavItem('parties', 'العملاء والموردين', Icons.people_outline, 'البيانات', true, () => PartiesScreen()),
        NavItem('offers', 'العروض', Icons.local_offer_outlined, 'البيانات', Me.can('offers'),
            () => OffersAdmin()),
        NavItem('reports', 'التقارير', Icons.bar_chart_rounded, 'أدوات', Me.can('reports'),
            () => ReportsScreen()),
        NavItem('excel', 'الإكسل', Icons.grid_on_outlined, 'أدوات', Me.can('reports') || Me.can('products'),
            () => ExcelScreen()),
        NavItem('designer', 'مصمم الفاتورة', Icons.print_outlined, 'أدوات', Me.owner,
            () => InvoiceDesigner()),
        NavItem('brand', 'هوية نشاطي', Icons.palette_outlined, 'أدوات', Me.owner, () => BrandScreen()),
        NavItem('staff', 'المساعدين والموظفين', Icons.badge_outlined, 'النظام', Me.owner, () => StaffScreen()),
        NavItem('accounts', 'حسابات العملاء', Icons.manage_accounts_outlined, 'النظام', Me.owner,
            () => AccountsScreen()),
        NavItem('settings', 'الإعدادات', Icons.settings_outlined, 'النظام', Me.owner, () => SettingsScreen()),
      ].where((i) => i.visible).toList();

  void _go(String key) {
    setState(() => tab = key);
    final s = scaffoldKey.currentState;
    if (s != null && s.isDrawerOpen) s.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Live.I, AppLock.locked]),
      builder: (context, _) {
        final live = Live.I;
        if (live.error.isNotEmpty && !live.ready) {
          return Scaffold(
            body: EmptyView('مش قادر أوصل للبيانات',
                text: '${live.error}\nاتأكد إن قواعد Firestore اتنشرت.', icon: Icons.cloud_off),
            bottomNavigationBar:
                SafeArea(child: TextButton(onPressed: () => auth.signOut(), child: Text('خروج'))),
          );
        }
        if (!live.ready) return Scaffold(body: Loading());
        if (AppLock.locked.value) return LockScreen();

        final list = items;
        final cur = list.firstWhere((i) => i.key == tab, orElse: () => list.first);
        visited.add(cur.key);
        final stack = IndexedStack(
          index: list.indexOf(cur),
          children: [for (final i in list) visited.contains(i.key) ? i.build() : SizedBox()],
        );

        return LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 1000;
          final scope = ShellScope(
            wide: wide,
            openMenu: () => scaffoldKey.currentState?.openDrawer(),
            go: _go,
            child: stack,
          );
          if (wide) {
            return Scaffold(
              key: scaffoldKey,
              body: Row(children: [
                SizedBox(width: 260, child: Sidebar(items: list, current: cur.key, onTap: _go)),
                Expanded(
                  child: Column(children: [
                    const TopBar(),
                    Expanded(child: scope),
                  ]),
                ),
              ]),
            );
          }
          // الموبايل: قايمة بتفتح من زرار + أهم الصفحات تحت
          final quick = <String>['home', 'sale', 'sales', 'parties'].where((k) => list.any((i) => i.key == k)).toList();
          final qi = quick.indexOf(cur.key);
          return Scaffold(
            key: scaffoldKey,
            drawer: Drawer(
              width: 290,
              backgroundColor: kSide,
              child: Sidebar(items: list, current: cur.key, onTap: _go, inDrawer: true),
            ),
            body: scope,
            bottomNavigationBar: NavigationBar(
              selectedIndex: qi < 0 ? quick.length : qi,
              onDestinationSelected: (i) {
                if (i == quick.length) {
                  scaffoldKey.currentState?.openDrawer();
                } else {
                  _go(quick[i]);
                }
              },
              destinations: [
                for (final k in quick)
                  NavigationDestination(
                    icon: Icon(list.firstWhere((i) => i.key == k).icon),
                    label: {'home': 'الرئيسية', 'sale': 'فاتورة', 'sales': 'المبيعات', 'parties': 'العملاء'}[k]!,
                  ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: live.newOrders > 0 || live.lowStock.isNotEmpty,
                    smallSize: 8,
                    child: Icon(Icons.menu),
                  ),
                  label: 'القايمة',
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

// ======================== القايمة الجانبية ========================

class Sidebar extends StatelessWidget {
  final List<NavItem> items;
  final String current;
  final ValueChanged<String> onTap;
  final bool inDrawer;
  const Sidebar({super.key, required this.items, required this.current, required this.onTap, this.inDrawer = false});

  @override
  Widget build(BuildContext context) {
    final live = Live.I;
    final children = <Widget>[];
    String? section;
    for (final i in items) {
      if (i.section != section) {
        section = i.section;
        children.add(Padding(
          padding: EdgeInsetsDirectional.fromSTEB(20, 16, 20, 6),
          child: Text(section, style: TextStyle(color: Color(0xFF8C8C8C), fontSize: 11.5, letterSpacing: .3)),
        ));
      }
      final on = i.key == current;
      int? badge;
      if (i.key == 'orders' && live.newOrders > 0) badge = live.newOrders;
      if (i.key == 'low' && live.lowStock.isNotEmpty) badge = live.lowStock.length;
      children.add(Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: on ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(i.key),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Icon(i.icon, size: 20, color: on ? Colors.black : Color(0xFFD6D6D6)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(i.label,
                      style: TextStyle(
                          color: on ? Colors.black : Color(0xFFEDEDED),
                          fontWeight: on ? FontWeight.bold : FontWeight.w500,
                          fontSize: 14)),
                ),
                if (badge != null)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: on ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Text('$badge',
                        style: TextStyle(
                            color: on ? Colors.white : Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
              ]),
            ),
          ),
        ),
      ));
    }
    return Container(
      color: kSide,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.white,
                  width: 48,
                  height: 48,
                  child: Brand.logo.isNotEmpty
                      ? B64Image(Brand.logo, fit: BoxFit.contain)
                      : Image.asset('assets/icon.png', fit: BoxFit.cover),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(Brand.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(Me.owner ? 'صاحب المحل' : 'موظف: ${Me.name}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 12)),
                ]),
              ),
            ]),
          ),
          if (inDrawer) _DrawerTools(),
          Divider(color: Color(0xFF262626), height: 1),
          Expanded(child: ListView(padding: EdgeInsets.only(bottom: 16), children: children)),
          Divider(color: Color(0xFF262626), height: 1),
          ListTile(
            dense: true,
            leading: Icon(Icons.logout, color: Color(0xFFBDBDBD), size: 20),
            title: Text('تسجيل خروج', style: TextStyle(color: Color(0xFFBDBDBD))),
            onTap: () async {
              if (await confirm(context, 'خروج', 'تخرج من حسابك؟', ok: 'خروج')) await auth.signOut();
            },
          ),
        ]),
      ),
    );
  }
}

/// أدوات الشريط العلوي جوه القايمة على الموبايل
class _DrawerTools extends StatelessWidget {
  const _DrawerTools();
  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, String tip, VoidCallback f) => IconButton(
          tooltip: tip,
          onPressed: f,
          icon: Icon(i, color: Colors.white, size: 20),
          style: IconButton.styleFrom(
              side: BorderSide(color: Color(0xFF333333)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(spacing: 6, children: [
        b(Icons.search, 'بحث', () {
          Navigator.pop(context);
          openGlobalSearch(context);
        }),
        b(AppPrefs.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, 'الوضع الليلي',
            () => AppPrefs.setDark(!AppPrefs.dark)),
        b(Icons.text_increase, 'تكبير الخط', () => AppPrefs.bumpText(.1)),
        b(Icons.text_decrease, 'تصغير الخط', () => AppPrefs.bumpText(-.1)),
        b(Icons.lock_outline, 'قفل البرنامج', () => AppLock.lockNow(context)),
      ]),
    );
  }
}

// ======================== الشريط العلوي (الكمبيوتر) ========================

class TopBar extends StatelessWidget {
  const TopBar({super.key});
  @override
  Widget build(BuildContext context) {
    Widget sq(IconData i, String tip, VoidCallback f) => Padding(
          padding: EdgeInsets.only(left: 6),
          child: Tooltip(
            message: tip,
            child: InkWell(
              onTap: f,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: Color(0xFF333333)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(i, color: Colors.white, size: 19),
              ),
            ),
          ),
        );
    return Container(
      height: 64,
      color: kSide,
      padding: EdgeInsets.symmetric(horizontal: 18),
      child: Row(children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: 420,
              height: 40,
              child: InkWell(
                onTap: () => openGlobalSearch(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      color: Color(0xFF1C1C1C), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(Icons.search, color: Color(0xFF9A9A9A), size: 19),
                    SizedBox(width: 8),
                    Text('ابحث عن عميل، صنف، أو رقم فاتورة…', style: TextStyle(color: Color(0xFF9A9A9A))),
                  ]),
                ),
              ),
            ),
          ),
        ),
        sq(Icons.lock_outline, 'قفل البرنامج', () => AppLock.lockNow(context)),
        sq(AppPrefs.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, 'الوضع الليلي',
            () => AppPrefs.setDark(!AppPrefs.dark)),
        sq(Icons.text_increase, 'تكبير الخط', () => AppPrefs.bumpText(.1)),
        sq(Icons.text_decrease, 'تصغير الخط', () => AppPrefs.bumpText(-.1)),
      ]),
    );
  }
}

// ======================== البحث في كل حاجة ========================

Future<void> openGlobalSearch(BuildContext context) {
  return showDialog(context: context, builder: (_) => _SearchDialog());
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog();
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final live = Live.I;
    final query = q.trim().toLowerCase().replaceAll('#', '');
    final results = <Widget>[];
    if (query.isNotEmpty) {
      final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
      for (final c in live.customers) {
        final m = c.data();
        if ((m['name'] ?? '').toString().toLowerCase().contains(query) ||
            pad4(m['code']).contains(query) ||
            (digits.length >= 4 && (m['phone'] ?? '').toString().contains(digits))) {
          results.add(ListTile(
            leading: Icon(Icons.person_outline),
            title: Text((m['name'] ?? '').toString()),
            subtitle: Text('عميل · #${pad4(m['code'])} · عليه ${money(live.accountOf(c.id).balance)}'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetail(customerId: c.id)));
            },
          ));
        }
        if (results.length > 30) break;
      }
      for (final p in live.products) {
        final m = p.data();
        if ((m['name'] ?? '').toString().toLowerCase().contains(query) ||
            (m['code'] ?? '').toString().toLowerCase().contains(query)) {
          results.add(ListTile(
            leading: Icon(Icons.inventory_2_outlined),
            title: Text((m['name'] ?? '').toString()),
            subtitle: Text('صنف · ${m['code'] ?? ''} · ${money(m['price'])}${m['stock'] != null ? ' · ${num2(m['stock'])} متاح' : ''}'),
            onTap: () {
              Navigator.pop(context);
              if (Me.can('products')) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(p: p)));
              }
            },
          ));
        }
      }
      if (digits.isNotEmpty) {
        for (final e in live.sales) {
          if (e.invoiceNo.toString() == digits.replaceFirst(RegExp(r'^0+'), '') ||
              invoiceLabel(e.invoiceNo).toLowerCase() == query) {
            results.add(ListTile(
              leading: Icon(Icons.receipt_long_outlined),
              title: Text('فاتورة ${invoiceLabel(e.invoiceNo)}'),
              subtitle: Text('${live.customerName((e.m['customerId'] ?? '').toString())} · ${money(e.debit)}'),
              onTap: () {
                Navigator.pop(context);
                openInvoice(context, e);
              },
            ));
          }
        }
      }
    }
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.fromLTRB(16, 60, 16, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                  hintText: 'اسم أو كود عميل، صنف، رقم موبايل، أو رقم فاتورة', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Flexible(
            child: query.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('اكتب أي حاجة تدوّر عليها', style: TextStyle(color: Colors.grey)))
                : results.isEmpty
                    ? Padding(padding: EdgeInsets.all(24), child: Text('مفيش نتايج'))
                    : ListView(shrinkWrap: true, children: results),
          ),
        ]),
      ),
    );
  }
}

// ======================== قفل البرنامج ========================

class AppLock {
  static final ValueNotifier<bool> locked = ValueNotifier(false);
  static String? get pin => AppPrefs.getStr('pin');
  static bool get onOpen => AppPrefs.getStr('lockOnOpen') == '1';

  static void lockOnOpenIfNeeded() {
    if (onOpen && (pin ?? '').isNotEmpty) locked.value = true;
  }

  static Future<void> lockNow(BuildContext context) async {
    if ((pin ?? '').isEmpty) {
      final p = await askNewPin(context);
      if (p == null) return;
    }
    locked.value = true;
  }

  static Future<String?> askNewPin(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('رمز القفل'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('اختار رمز من 4 أرقام أو أكتر. هتحتاجه عشان تفتح البرنامج بعد القفل.'),
          SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'الرمز'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('حفظ')),
        ],
      ),
    );
    final v = c.text.trim();
    if (ok != true || v.length < 4) return null;
    AppPrefs.setStr('pin', v);
    return v;
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String typed = '';
  bool wrong = false;

  void _press(String d) {
    setState(() {
      wrong = false;
      if (d == '<') {
        if (typed.isNotEmpty) typed = typed.substring(0, typed.length - 1);
      } else if (typed.length < 8) {
        typed += d;
      }
    });
    if (typed == AppLock.pin) {
      AppLock.locked.value = false;
    } else if (typed.length >= (AppLock.pin ?? '').length) {
      setState(() {
        wrong = true;
        typed = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => Padding(
          padding: EdgeInsets.all(6),
          child: SizedBox(
            width: 72,
            height: 64,
            child: OutlinedButton(
              onPressed: () => _press(d),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Color(0xFF333333)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: d == '<' ? Icon(Icons.backspace_outlined) : Text(d, style: TextStyle(fontSize: 22)),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: kSide,
      body: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset('assets/icon.png', width: 84, height: 84),
            ),
            SizedBox(height: 14),
            Text(Brand.name, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text(wrong ? 'الرمز غلط، جرّب تاني' : 'البرنامج مقفول، اكتب الرمز',
                style: TextStyle(color: wrong ? Color(0xFFFF8A80) : Color(0xFF9A9A9A))),
            SizedBox(height: 16),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < (AppLock.pin ?? '0000').length; i++)
                Container(
                  margin: EdgeInsets.all(5),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < typed.length ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white),
                  ),
                ),
            ]),
            SizedBox(height: 16),
            for (final row in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['', '0', '<'],
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final d in row) d.isEmpty ? SizedBox(width: 84) : key(d)],
              ),
            SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'نسيت الرمز؟', 'هتخرج من حسابك وتدخل تاني بكلمة السر، والرمز هيتمسح.',
                    ok: 'خروج')) {
                  AppPrefs.setStr('pin', null);
                  AppLock.locked.value = false;
                  await auth.signOut();
                }
              },
              child: Text('نسيت الرمز؟', style: TextStyle(color: Color(0xFF9A9A9A))),
            ),
          ]),
        ),
      ),
    );
  }
}
