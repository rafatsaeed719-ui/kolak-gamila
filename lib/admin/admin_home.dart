import 'package:flutter/material.dart';

import '../core.dart';
import 'customers.dart';
import 'invoice_view.dart';
import 'live.dart';
import 'money_screens.dart';
import 'shell.dart';

/// لوحة التحكم
class Dashboard extends StatelessWidget {
  final ValueChanged<String> onGo;
  const Dashboard({super.key, required this.onGo});

  @override
  Widget build(BuildContext context) {
    final live = Live.I;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month);

    var outside = 0.0;
    var debtors = 0;
    for (final c in live.customers) {
      final b = live.accountOf(c.id).balance;
      if (b > 0.004) {
        outside += b;
        debtors++;
      }
    }
    var salesToday = 0.0, collectedToday = 0.0, salesMonth = 0.0, cogsMonth = 0.0, returnsMonth = 0.0;
    var invoicesToday = 0;
    final byDay = List<double>.filled(7, 0);
    for (final e in live.entries) {
      final d = e.date;
      final inMonth = !d.isBefore(monthStart);
      if (!d.isBefore(today)) {
        collectedToday += e.collected;
        if (e.kind == 'sale') {
          salesToday += e.debit;
          invoicesToday++;
        }
      }
      if (e.kind == 'sale') {
        final ago = today.difference(DateTime(d.year, d.month, d.day)).inDays;
        if (ago >= 0 && ago < 7) byDay[6 - ago] += e.debit;
        if (inMonth) {
          salesMonth += e.debit;
          for (final it in e.items) {
            cogsMonth += (toD(it['qty']) - toD(it['returned'])) * live.costOf((it['productId'] ?? '').toString());
          }
        }
      }
      if (e.kind == 'return' && inMonth) returnsMonth += e.credit;
    }
    var expensesMonth = 0.0;
    for (final x in live.expenses) {
      final d = tsToDate(x.data()['date']);
      if (d != null && !d.isBefore(monthStart)) expensesMonth += toD(x.data()['amount']);
    }
    var stockSell = 0.0, stockCost = 0.0;
    for (final p in live.products) {
      final s = toD(p.data()['stock']);
      if (s > 0) {
        stockSell += s * toD(p.data()['price']);
        stockCost += s * live.costOf(p.id);
      }
    }
    final profit = salesMonth - returnsMonth - cogsMonth - expensesMonth;

    return Scaffold(
      appBar: pageAppBar(context, 'لوحة التحكم'),
      body: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 640 ? 3 : 2);
        Widget grid(List<Widget> tiles) => GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: cols == 2 ? 1.75 : 2.3,
              children: tiles,
            );
        final twoCol = c.maxWidth >= 900;
        final recent = live.sales.take(7).toList();
        final top = live.customers
            .where((x) => x.id != 'cash')
            .map((x) => MapEntry(x, live.accountOf(x.id).balance))
            .where((e) => e.value > 0.004)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Panel(
            title: 'مبيعات آخر 7 أيام',
            child: _Bars(values: byDay, today: today),
          ),
          _Panel(
            title: 'آخر الفواتير',
            action: TextButton(onPressed: () => onGo('sales'), child: Text('سجل المبيعات')),
            child: recent.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لسه مفيش فواتير', style: TextStyle(color: kMuted)))
                : Column(
                    children: recent
                        .map((e) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12),
                              onTap: () => openInvoice(context, e),
                              leading: Text(invoiceLabel(e.invoiceNo),
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              title: Text(live.customerName((e.m['customerId'] ?? '').toString()),
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(fmtDate(e.date, time: true)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(money(e.debit), style: TextStyle(fontWeight: FontWeight.bold)),
                                SizedBox(width: 8),
                                invoiceStatusPill(e.status),
                              ]),
                            ))
                        .toList(),
                  ),
          ),
        ]);
        final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Panel(
            title: 'أعلى مديونيات',
            action: TextButton(onPressed: () => onGo('parties'), child: Text('كل العملاء')),
            child: top.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(16), child: Text('مفيش مديونيات 👌', style: TextStyle(color: kMuted)))
                : Column(
                    children: top
                        .take(6)
                        .map((e) => ListTile(
                              dense: true,
                              leading: CodeBadge(e.key.data()['code']),
                              title: Text((e.key.data()['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                              trailing: Text(money(e.value),
                                  style: TextStyle(color: kOwe, fontWeight: FontWeight.bold)),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => CustomerDetail(customerId: e.key.id))),
                            ))
                        .toList(),
                  ),
          ),
          _Panel(
            title: 'المخزون الحرج',
            action: TextButton(onPressed: () => onGo('low'), child: Text('عرض الكل')),
            child: live.lowStock.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('كل الأصناف كمياتها كويسة', style: TextStyle(color: kMuted)))
                : Column(
                    children: live.lowStock
                        .take(6)
                        .map((p) => ListTile(
                              dense: true,
                              leading: Icon(Icons.warning_amber_rounded, color: kWarn),
                              title: Text((p.data()['name'] ?? '').toString()),
                              trailing: Text('${num2(p.data()['stock'])} متاح',
                                  style: TextStyle(color: kOwe, fontWeight: FontWeight.bold)),
                            ))
                        .toList(),
                  ),
          ),
        ]);

        return ListView(padding: EdgeInsets.all(14), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (Me.can('sell'))
              FilledButton.icon(
                  onPressed: () => onGo('sale'),
                  icon: Icon(Icons.add_shopping_cart, size: 18),
                  label: Text('فاتورة بيع')),
            if (Me.can('sell'))
              OutlinedButton.icon(
                  onPressed: () => pickCustomerThenPay(context),
                  icon: Icon(Icons.payments_outlined, size: 18),
                  label: Text('تسجيل دفعة')),
            if (Me.can('expenses'))
              OutlinedButton.icon(
                  onPressed: () => openExpenseForm(context),
                  icon: Icon(Icons.account_balance_wallet_outlined, size: 18),
                  label: Text('مصروف')),
            if (Me.can('purchases'))
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseForm())),
                  icon: Icon(Icons.shopping_cart_outlined, size: 18),
                  label: Text('فاتورة شرا')),
            if (Me.can('customers'))
              OutlinedButton.icon(
                  onPressed: () => openCustomerForm(context),
                  icon: Icon(Icons.person_add_alt, size: 18),
                  label: Text('عميل جديد')),
          ]),
          SizedBox(height: 14),
          grid([
            StatBox('مبيعات النهارده ($invoicesToday فاتورة)', money(salesToday), icon: Icons.today),
            StatBox('اتحصّل النهارده', money(collectedToday), color: kPaid, icon: Icons.savings_outlined),
            StatBox('ليك برّه عند $debtors عميل', money(outside),
                color: kOwe, icon: Icons.account_balance_wallet_outlined, onTap: () => onGo('parties')),
            StatBox('مبيعات الشهر', money(salesMonth - returnsMonth), icon: Icons.trending_up),
            if (Me.can('expenses') || Me.owner)
              StatBox('مصروفات الشهر', money(expensesMonth), icon: Icons.receipt_outlined, onTap: () => onGo('expenses')),
            if (Me.owner) StatBox('صافي ربح الشهر', money(profit), color: profit >= 0 ? kPaid : kOwe, icon: Icons.insights),
            StatBox('البضاعة بسعر البيع', money(stockSell), icon: Icons.sell_outlined, onTap: () => onGo('products')),
            if (Me.owner)
              StatBox('البضاعة بسعر الشرا', money(stockCost), icon: Icons.inventory_2_outlined, onTap: () => onGo('products')),
            StatBox('طلبات جديدة', '${live.newOrders}',
                color: live.newOrders > 0 ? kInfo : null, icon: Icons.shopping_bag_outlined, onTap: () => onGo('orders')),
          ]),
          SizedBox(height: 6),
          if (twoCol)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: left),
              SizedBox(width: 10),
              Expanded(flex: 2, child: right),
            ])
          else ...[
            left,
            right,
          ],
        ]);
      }),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  const _Panel({required this.title, required this.child, this.action});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(top: 10),
      child: Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 8, 4),
            child: Row(children: [
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              if (action != null) action!,
            ]),
          ),
          child,
        ]),
      ),
    );
  }
}

/// أعمدة بسيطة للمبيعات اليومية
class _Bars extends StatelessWidget {
  final List<double> values;
  final DateTime today;
  const _Bars({required this.values, required this.today});
  @override
  Widget build(BuildContext context) {
    final max = values.fold(0.0, (a, b) => b > a ? b : a);
    const days = ['الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت', 'الحد'];
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: SizedBox(
        height: 170,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  FittedBox(
                    child: Text(values[i] > 0 ? num2(values[i]) : '',
                        style: TextStyle(fontSize: 11, color: kMuted)),
                  ),
                  SizedBox(height: 4),
                  Container(
                    height: max <= 0 ? 2 : 2 + 110 * values[i] / max,
                    decoration: BoxDecoration(
                      color: i == 6 ? kInk : kInk.withValues(alpha: .28),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  SizedBox(height: 6),
                  FittedBox(
                    child: Text(i == 6 ? 'النهارده' : days[today.subtract(Duration(days: 6 - i)).weekday - 1],
                        style: TextStyle(fontSize: 11, color: kMuted)),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
