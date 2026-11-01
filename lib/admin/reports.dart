import 'package:flutter/material.dart';

import '../core.dart';
import 'live.dart';
import 'shell.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String period = 'month';
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime to = DateTime.now();

  void _set(String p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      period = p;
      to = today;
      switch (p) {
        case 'today':
          from = today;
          break;
        case 'week':
          from = today.subtract(Duration(days: 6));
          break;
        case 'month':
          from = DateTime(now.year, now.month);
          break;
        case 'lastMonth':
          from = DateTime(now.year, now.month - 1);
          to = DateTime(now.year, now.month).subtract(Duration(days: 1));
          break;
        case 'year':
          from = DateTime(now.year);
          break;
      }
    });
  }

  bool _in(DateTime? d) {
    if (d == null) return false;
    final end = DateTime(to.year, to.month, to.day).add(Duration(days: 1));
    return !d.isBefore(DateTime(from.year, from.month, from.day)) && d.isBefore(end);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final live = Live.I;
        var sales = 0.0, discounts = 0.0, returns = 0.0, collected = 0.0, cogs = 0.0;
        var invoices = 0;
        final byProduct = <String, List<double>>{}; // name -> [qty, value]
        final byCustomer = <String, double>{};
        final byRep = <String, double>{};
        final byMethod = <String, double>{};
        for (final e in live.entries) {
          if (!_in(e.date)) continue;
          if (e.kind == 'sale' && e.debit > 0) {
            invoices++;
            sales += e.debit;
            discounts += e.discount;
            final cid = (e.m['customerId'] ?? '').toString();
            byCustomer[cid] = (byCustomer[cid] ?? 0) + e.debit;
            final rep = e.rep.isEmpty ? 'بدون مندوب' : e.rep;
            byRep[rep] = (byRep[rep] ?? 0) + e.debit;
            for (final it in e.items) {
              final q = toD(it['qty']) - toD(it['returned']);
              final name = (it['name'] ?? '').toString();
              final row = byProduct[name] ??= [0, 0];
              row[0] += q;
              row[1] += q * toD(it['price']);
              cogs += q * live.costOf((it['productId'] ?? '').toString());
            }
          }
          if (e.kind == 'return') returns += e.credit;
          if (e.collected > 0) {
            collected += e.collected;
            final m = e.kind == 'sale' ? e.payMethod : (e.m['method'] ?? 'cash').toString();
            byMethod[payMethodLabel(m)] = (byMethod[payMethodLabel(m)] ?? 0) + e.collected;
          }
        }
        var expenses = 0.0;
        final byCat = <String, double>{};
        for (final x in live.expenses) {
          if (!_in(tsToDate(x.data()['date']))) continue;
          final v = toD(x.data()['amount']);
          expenses += v;
          final c = (x.data()['category'] ?? '').toString();
          byCat[c] = (byCat[c] ?? 0) + v;
        }
        var purchases = 0.0;
        for (final p in live.purchases) {
          if (_in(tsToDate(p.data()['date']))) purchases += toD(p.data()['total']);
        }
        var damaged = 0.0;
        for (final x in live.damaged) {
          if (_in(tsToDate(x.data()['date']))) damaged += toD(x.data()['value']);
        }
        final netSales = sales - returns;
        final gross = netSales - cogs;
        final net = gross - expenses - damaged;

        List<MapEntry<String, double>> top(Map<String, double> m) =>
            (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10).toList();
        final topProducts = (byProduct.entries.toList()..sort((a, b) => b.value[1].compareTo(a.value[1]))).take(10);

        return Scaffold(
          appBar: pageAppBar(context, 'التقارير'),
          body: LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 640 ? 3 : 2);
            final wide = c.maxWidth >= 900;
            final tiles = [
              StatBox('صافي المبيعات ($invoices فاتورة)', money(netSales), icon: Icons.trending_up),
              StatBox('الخصومات', money(discounts), icon: Icons.discount_outlined),
              StatBox('المرتجعات', money(returns), icon: Icons.undo),
              StatBox('اتحصّل', money(collected), color: kPaid, icon: Icons.savings_outlined),
              StatBox('المصروفات', money(expenses), color: kOwe, icon: Icons.receipt_outlined),
              StatBox('المشتريات', money(purchases), icon: Icons.shopping_cart_outlined),
              StatBox('الهالك', money(damaged), color: kOwe, icon: Icons.broken_image_outlined),
              if (Me.owner) ...[
                StatBox('تكلفة البضاعة المباعة', money(cogs), icon: Icons.inventory_2_outlined),
                StatBox('مجمل الربح', money(gross), color: gross >= 0 ? kPaid : kOwe, icon: Icons.insights),
                StatBox('صافي الربح', money(net), color: net >= 0 ? kPaid : kOwe, icon: Icons.account_balance),
              ],
            ];
            Widget list(String title, List<MapEntry<String, double>> rows, {String Function(String)? label}) {
              final max = rows.isEmpty ? 1.0 : rows.first.value;
              return Card(
                margin: EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 8),
                    if (rows.isEmpty) Text('مفيش بيانات في الفترة دي', style: TextStyle(color: kMuted)),
                    for (final r in rows)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(child: Text(label == null ? r.key : label(r.key), overflow: TextOverflow.ellipsis)),
                            Text(money(r.value), style: TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                          SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: max <= 0 ? 0.0 : (r.value / max).clamp(0.0, 1.0).toDouble(),
                              minHeight: 6,
                              backgroundColor: kBlush,
                              color: kInk,
                            ),
                          ),
                        ]),
                      ),
                  ]),
                ),
              );
            }

            final panels = [
              Card(
                margin: EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('أكتر الأصناف مبيعاً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 6),
                    if (byProduct.isEmpty) Text('مفيش بيانات في الفترة دي', style: TextStyle(color: kMuted)),
                    for (final p in topProducts)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text(p.key, overflow: TextOverflow.ellipsis)),
                          Text('${num2(p.value[0])} قطعة', style: TextStyle(color: kMuted)),
                          SizedBox(width: 12),
                          SizedBox(
                              width: 100,
                              child: Text(money(p.value[1]),
                                  textAlign: TextAlign.left, style: TextStyle(fontWeight: FontWeight.w600))),
                        ]),
                      ),
                  ]),
                ),
              ),
              list('أكتر العملاء شراً', top(byCustomer), label: live.customerName),
              list('المبيعات حسب المندوب', top(byRep)),
              list('التحصيل حسب طريقة الدفع', top(byMethod)),
              list('المصروفات حسب البند', top(byCat)),
            ];
            return ListView(padding: EdgeInsets.all(12), children: [
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final p in {
                  'today': 'النهارده',
                  'week': 'آخر 7 أيام',
                  'month': 'الشهر ده',
                  'lastMonth': 'الشهر اللي فات',
                  'year': 'السنة دي',
                }.entries)
                  ChoiceChip(label: Text(p.value), selected: period == p.key, onSelected: (_) => _set(p.key)),
                ActionChip(
                  avatar: Icon(Icons.date_range, size: 18),
                  label: Text(period == 'custom' ? '${fmtDate(from)} ← ${fmtDate(to)}' : 'فترة مخصصة'),
                  onPressed: () async {
                    final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange: DateTimeRange(start: from, end: to));
                    if (r != null) {
                      setState(() {
                        period = 'custom';
                        from = r.start;
                        to = r.end;
                      });
                    }
                  },
                ),
              ]),
              SizedBox(height: 12),
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: cols == 2 ? 1.75 : 2.3,
                children: tiles,
              ),
              if (Me.owner && cogs == 0 && sales > 0)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('عشان الربح يطلع مظبوط، اكتب سعر الشرا لكل صنف (أو سجّل المشتريات).',
                      style: TextStyle(color: kWarn, fontSize: 12.5)),
                ),
              SizedBox(height: 12),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(children: [panels[0], panels[2]])),
                  SizedBox(width: 10),
                  Expanded(child: Column(children: [panels[1], panels[3], panels[4]])),
                ])
              else
                ...panels,
            ]);
          }),
        );
      },
    );
  }
}
