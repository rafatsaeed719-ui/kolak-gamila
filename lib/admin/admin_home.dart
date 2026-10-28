import 'package:flutter/material.dart';

import '../core.dart';
import 'accounts.dart';
import 'customers.dart';
import 'live.dart';
import 'offers.dart';
import 'orders.dart';
import 'products.dart';
import 'settings_screen.dart';
import 'staff.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  String tab = '';

  @override
  void initState() {
    super.initState();
    Live.I.start();
  }

  @override
  void dispose() {
    Live.I.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        if (live.error.isNotEmpty && !live.ready) {
          return Scaffold(
            body: EmptyView('مش قادر أوصل للبيانات',
                text: '${live.error}\nاتأكد إن قواعد Firestore اتنشرت.', icon: Icons.cloud_off),
            bottomNavigationBar: SafeArea(
                child: TextButton(onPressed: () => auth.signOut(), child: const Text('خروج'))),
          );
        }
        if (!live.ready) return const Scaffold(body: Loading());
        // التبويبات حسب صلاحيات اللي داخل
        final tabs = <(String, Widget, NavigationDestination)>[
          if (Me.can('reports'))
            (
              'home',
              Dashboard(onGo: (k) => setState(() => tab = k)),
              const NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية')
            ),
          (
            'customers',
            const CustomersScreen(),
            const NavigationDestination(icon: Icon(Icons.people_outline), label: 'العملاء')
          ),
          (
            'products',
            const ProductsScreen(),
            const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'البضاعة')
          ),
          if (Me.can('orders'))
            (
              'orders',
              const OrdersScreen(),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: live.newOrders > 0,
                  label: Text('${live.newOrders}'),
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
                label: 'الطلبات',
              )
            ),
          (
            'more',
            const MoreScreen(),
            const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد')
          ),
        ];
        var index = tabs.indexWhere((t) => t.$1 == tab);
        if (index < 0) index = 0;
        return Scaffold(
          body: IndexedStack(index: index, children: tabs.map((t) => t.$2).toList()),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => tab = tabs[i].$1),
            destinations: tabs.map((t) => t.$3).toList(),
          ),
        );
      },
    );
  }
}

class Dashboard extends StatelessWidget {
  final ValueChanged<String> onGo;
  const Dashboard({super.key, required this.onGo});

  @override
  Widget build(BuildContext context) {
    final live = Live.I;
    // الفلوس اللي برّه
    var outside = 0.0, credits = 0.0;
    var debtors = 0;
    for (final c in live.customers) {
      final b = live.accountOf(c.id).balance;
      if (b > 0.004) {
        outside += b;
        debtors++;
      } else if (b < -0.004) {
        credits += -b;
      }
    }
    // البضاعة
    var stockCost = 0.0, stockSell = 0.0, pieces = 0.0;
    var low = 0;
    for (final p in live.products) {
      final m = p.data();
      final s = toD(m['stock']);
      if (s > 0) {
        stockCost += s * live.costOf(p.id);
        stockSell += s * toD(m['price']);
        pieces += s;
      }
      if (m['stock'] != null && s <= toD(m['minStock'] ?? 2)) low++;
    }
    // التحصيل والمبيعات
    final now = DateTime.now();
    var today = 0.0, month = 0.0, salesMonth = 0.0;
    for (final e in live.entries) {
      final d = e.date;
      final sameMonth = d.year == now.year && d.month == now.month;
      if (sameMonth) {
        month += e.collected;
        if (e.kind == 'sale') salesMonth += e.debit;
      }
      if (sameMonth && d.day == now.day) today += e.collected;
    }
    final top = live.customers.map((c) => MapEntry(c, live.accountOf(c.id).balance)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text(kStoreName)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        const SectionTitle('ليك عند العملاء'),
        _grid([
          StatBox('إجمالي الفلوس اللي برّه', money(outside),
              color: kOwe, icon: Icons.account_balance_wallet_outlined, onTap: () => onGo('customers')),
          StatBox('عملاء عليهم فلوس', '$debtors',
              icon: Icons.people_outline, onTap: () => onGo('customers')),
          StatBox('اتحصّل النهارده', money(today), color: kPaid, icon: Icons.today),
          StatBox('اتحصّل الشهر ده', money(month), color: kPaid, icon: Icons.calendar_month),
        ]),
        const SectionTitle('رصيد البضاعة في المحل'),
        _grid([
          if (Me.owner)
            StatBox('قيمة البضاعة بسعر الشرا', money(stockCost),
                icon: Icons.inventory_2_outlined, onTap: () => onGo('products')),
          StatBox('قيمة البضاعة بسعر البيع', money(stockSell),
              icon: Icons.sell_outlined, onTap: () => onGo('products')),
          StatBox('عدد القطع', num2(pieces), icon: Icons.category_outlined, onTap: () => onGo('products')),
          StatBox('أصناف قربت تخلص', '$low',
              color: low > 0 ? kOwe : kPlum, icon: Icons.warning_amber, onTap: () => onGo('products')),
        ]),
        const SectionTitle('الشهر ده'),
        _grid([
          StatBox('مبيعات الشهر', money(salesMonth), icon: Icons.trending_up),
          StatBox('طلبات جديدة', '${live.newOrders}',
              color: live.newOrders > 0 ? Colors.blue : kPlum,
              icon: Icons.shopping_bag_outlined,
              onTap: () => onGo('orders')),
          if (credits > 0) StatBox('أرصدة للعملاء عندك', money(credits), icon: Icons.savings_outlined),
        ]),
        if (top.isNotEmpty && top.first.value > 0) ...[
          const SectionTitle('أعلى مديونيات'),
          ...top.where((e) => e.value > 0.004).take(5).map((e) => Card(
                child: ListTile(
                  leading: CodeBadge(e.key.data()['code']),
                  title: Text((e.key.data()['name'] ?? '').toString()),
                  trailing: Text(money(e.value),
                      style: const TextStyle(color: kOwe, fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => CustomerDetail(customerId: e.key.id))),
                ),
              )),
        ],
      ]),
    );
  }

  Widget _grid(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.9,
          children: children,
        ),
      );
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget item(IconData i, String t, String s, Widget page) => Card(
          child: ListTile(
            leading: Icon(i, color: kPlum),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(s),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        if (!Me.owner)
          Card(
            color: kBlush,
            child: ListTile(
              leading: const Icon(Icons.badge_outlined, color: kPlum),
              title: Text('داخل باسم: ${Me.name}'),
              subtitle: const Text('حساب موظف'),
            ),
          ),
        if (Me.can('offers'))
          item(Icons.local_offer_outlined, 'العروض', 'العروض اللي بتنزل للعملاء في التطبيق',
              const OffersAdmin()),
        if (Me.owner)
          item(Icons.badge_outlined, 'المساعدين والموظفين', 'إضافة موظف وتحديد صلاحياته',
              const StaffScreen()),
        if (Me.owner)
          item(Icons.manage_accounts_outlined, 'حسابات العملاء في التطبيق',
              'اللي سجلوا برقم التليفون: كلمة السر، الحذف، إضافة حساب', const AccountsScreen()),
        if (Me.owner)
          item(Icons.settings_outlined, 'الإعدادات', 'النقط وبيانات المحل', const SettingsScreen()),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () async {
              if (await confirm(context, 'خروج', 'تخرج من حسابك؟', ok: 'خروج')) {
                await auth.signOut();
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل خروج'),
          ),
        ),
      ]),
    );
  }
}
