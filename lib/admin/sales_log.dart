import 'dart:convert';

import 'package:flutter/material.dart';

import '../core.dart';
import '../pdf.dart';
import 'invoice_view.dart';
import 'live.dart';
import 'shell.dart';

const Map<String, String> _cols = {
  'no': 'الرقم',
  'date': 'التاريخ',
  'customer': 'العميل',
  'gross': 'الإجمالي',
  'discount': 'الخصم',
  'net': 'الصافي',
  'method': 'طريقة الدفع',
  'status': 'الحالة',
  'collect': 'التحصيل',
  'rep': 'المندوب',
  'actions': 'إجراءات',
};

class SalesLog extends StatefulWidget {
  const SalesLog({super.key});
  @override
  State<SalesLog> createState() => _SalesLogState();
}

class _SalesLogState extends State<SalesLog> {
  late DateTime from;
  late DateTime to;
  String? customerId;
  String? method;
  String? status;
  String q = '';
  late Set<String> cols;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    from = DateTime(now.year, now.month, 1);
    to = DateTime(now.year, now.month, now.day);
    cols = _cols.keys.toSet();
    try {
      final c = AppPrefs.getStr('salesCols');
      if (c != null) cols = (jsonDecode(c) as List).map((e) => e.toString()).toSet();
      final f = AppPrefs.getStr('salesFilter');
      if (f != null) {
        final m = jsonDecode(f) as Map<String, dynamic>;
        final days = toI(m['days']);
        if (days > 0) {
          from = to.subtract(Duration(days: days - 1));
        }
        method = m['method'] as String?;
        status = m['status'] as String?;
        customerId = m['customerId'] as String?;
      }
    } catch (_) {}
  }

  void _quick(String k) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      switch (k) {
        case 'today':
          from = today;
          to = today;
          status = null;
          break;
        case 'week':
          from = today.subtract(Duration(days: (today.weekday + 1) % 7)); // من السبت
          to = today;
          status = null;
          break;
        case 'month':
          from = DateTime(now.year, now.month, 1);
          to = today;
          status = null;
          break;
        case 'deferred':
          from = DateTime(2020);
          to = today;
          status = 'deferred';
          break;
      }
    });
  }

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(
        context: context,
        initialDate: isFrom ? from : to,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (d == null) return;
    setState(() {
      if (isFrom) {
        from = d;
      } else {
        to = d;
      }
    });
  }

  List<Entry> _filtered() {
    final live = Live.I;
    final end = DateTime(to.year, to.month, to.day).add(Duration(days: 1));
    final query = q.trim().toLowerCase();
    return live.sales.where((e) {
      if (e.date.isBefore(from) || !e.date.isBefore(end)) return false;
      final cid = (e.m['customerId'] ?? '').toString();
      if (customerId != null && cid != customerId) return false;
      if (method != null && e.payMethod != method) return false;
      if (status != null && e.status != status) return false;
      if (query.isNotEmpty) {
        final name = live.customerName(cid).toLowerCase();
        final no = invoiceLabel(e.invoiceNo).toLowerCase();
        if (!name.contains(query) && !no.contains(query) && e.invoiceNo.toString() != query) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Live.I,
      builder: (context, _) {
        final list = _filtered();
        final net = list.fold(0.0, (a, e) => a + e.debit);
        final rem = list.fold(0.0, (a, e) => a + e.remaining);
        final disc = list.fold(0.0, (a, e) => a + e.discount);
        return Scaffold(
          appBar: pageAppBar(context, 'سجل المبيعات'),
          body: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            return ListView(padding: EdgeInsets.all(12), children: [
              Text('${list.length} فاتورة معروضة من إجمالي ${Live.I.sales.length}', style: TextStyle(color: kMuted)),
              SizedBox(height: 8),
              _filters(wide),
              SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _sum('عدد الفواتير', '${list.length}'),
                _sum('الصافي', money(net)),
                _sum('الخصومات', money(disc)),
                _sum('اتحصّل', money(net - rem), color: kPaid),
                _sum('الباقي (آجل)', money(rem), color: kOwe),
              ]),
              SizedBox(height: 10),
              if (list.isEmpty)
                Card(
                  margin: EdgeInsets.zero,
                  child: EmptyView('مفيش فواتير بالفلتر ده', text: 'غيّر التاريخ أو الفلاتر.', icon: Icons.receipt_long_outlined),
                )
              else if (wide)
                _table(list)
              else
                ...list.map(_card),
            ]);
          }),
        );
      },
    );
  }

  Widget _sum(String l, String v, {Color? color}) => Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: TextStyle(fontSize: 11.5, color: kMuted)),
          Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
      );

  Widget _filters(bool wide) {
    final live = Live.I;
    Widget box(String label, Widget child) => SizedBox(
          width: wide ? 175 : double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            child,
          ]),
        );
    Widget dateBtn(DateTime d, bool isFrom) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              minimumSize: Size.fromHeight(44),
              alignment: AlignmentDirectional.centerStart,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: () => _pickDate(isFrom),
          icon: Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(fmtDate(d)),
        );
    DropdownButtonFormField<String?> dd(String? v, Map<String?, String> items, ValueChanged<String?> f) =>
        DropdownButtonFormField<String?>(
          value: items.containsKey(v) ? v : null,
          isExpanded: true,
          items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (x) => setState(() => f(x)),
        );
    final custItems = <String?, String>{null: 'كل العملاء'};
    for (final c in live.customers) {
      custItems[c.id] = (c.data()['name'] ?? '').toString();
    }
    final fields = [
      box('من تاريخ', dateBtn(from, true)),
      box('إلى تاريخ', dateBtn(to, false)),
      box('العميل', dd(customerId, custItems, (x) => customerId = x)),
      box('طريقة الدفع', dd(method, {null: 'الكل', ...kPayMethods}, (x) => method = x)),
      box('الحالة', dd(status, {null: 'كل الحالات', 'paid': 'مسددة', 'deferred': 'آجلة', 'returned': 'مرتجع'}, (x) => status = x)),
      box(
        'بحث',
        TextField(
          decoration: InputDecoration(hintText: 'رقم أو عميل…', prefixIcon: Icon(Icons.search, size: 18)),
          onChanged: (v) => setState(() => q = v),
        ),
      ),
    ];
    Widget chip(String k, String l) => ActionChip(
          avatar: Icon(Icons.star_rounded, size: 16),
          label: Text(l),
          onPressed: () => _quick(k),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (wide)
            Wrap(spacing: 10, runSpacing: 10, children: fields)
          else
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('الفلاتر: ${fmtDate(from)} ← ${fmtDate(to)}'),
              childrenPadding: EdgeInsets.only(bottom: 8),
              children: [for (final f in fields) Padding(padding: EdgeInsets.only(bottom: 8), child: f)],
            ),
          SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            chip('today', 'فواتير اليوم'),
            chip('week', 'هذا الأسبوع'),
            chip('month', 'الشهر ده'),
            chip('deferred', 'الفواتير الآجلة'),
            OutlinedButton.icon(
              onPressed: () {
                final days = DateTime(to.year, to.month, to.day).difference(from).inDays + 1;
                AppPrefs.setStr(
                    'salesFilter', jsonEncode({'days': days, 'method': method, 'status': status, 'customerId': customerId}));
                toast(context, 'اتحفظ الفلتر، هيفتح كده كل مرة');
              },
              icon: Icon(Icons.bookmark_add_outlined, size: 18),
              label: Text('حفظ الفلتر الحالي'),
            ),
            if (wide)
              OutlinedButton.icon(
                onPressed: _toggleCols,
                icon: Icon(Icons.tune, size: 18),
                label: Text('إظهار/إخفاء الأعمدة'),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _toggleCols() async {
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('الأعمدة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final c in _cols.entries)
              CheckboxListTile(
                dense: true,
                value: cols.contains(c.key),
                title: Text(c.value),
                onChanged: (v) {
                  setS(() {
                    if (v == true) {
                      cols.add(c.key);
                    } else {
                      cols.remove(c.key);
                    }
                  });
                  setState(() {});
                  AppPrefs.setStr('salesCols', jsonEncode(cols.toList()));
                },
              ),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: Text('تمام'))],
        ),
      ),
    );
  }

  Widget _actions(Entry e) {
    final live = Live.I;
    final cid = (e.m['customerId'] ?? '').toString();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
          tooltip: 'عرض',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.visibility_outlined, size: 20),
          onPressed: () => openInvoice(context, e)),
      IconButton(
          tooltip: 'طباعة',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.print_outlined, size: 20),
          onPressed: () =>
              shareInvoicePdf(context, live.customer(cid)?.data() ?? {'name': live.customerName(cid), 'code': 0}, e)),
      if (Me.can('sell') && e.status != 'returned')
        IconButton(
            tooltip: 'مرتجع',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.undo, size: 20, color: kOwe),
            onPressed: () => returnInvoice(context, e)),
    ]);
  }

  Widget _collect(Entry e) {
    if (e.remaining <= 0.004) return Text('—', style: TextStyle(color: kMuted));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (Me.can('sell'))
        Row(mainAxisSize: MainAxisSize.min, children: [
          FilledButton(
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact, padding: EdgeInsets.symmetric(horizontal: 10)),
            onPressed: () => collectInvoice(context, e, full: true),
            child: Text('كلي'),
          ),
          SizedBox(width: 4),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact, padding: EdgeInsets.symmetric(horizontal: 10)),
            onPressed: () => collectInvoice(context, e, full: false),
            child: Text('جزئي'),
          ),
        ]),
      Text('المتبقي: ${money(e.remaining)}', style: TextStyle(fontSize: 11, color: kOwe)),
    ]);
  }

  Widget _table(List<Entry> list) {
    final live = Live.I;
    final keys = _cols.keys.where(cols.contains).toList();
    DataCell cell(String k, Entry e) {
      final cid = (e.m['customerId'] ?? '').toString();
      switch (k) {
        case 'no':
          return DataCell(Text(invoiceLabel(e.invoiceNo), style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => openInvoice(context, e));
        case 'date':
          return DataCell(Text(fmtDate(e.date)));
        case 'customer':
          return DataCell(Text(live.customerName(cid), style: TextStyle(fontWeight: FontWeight.w600)));
        case 'gross':
          return DataCell(Text(money(e.gross)));
        case 'discount':
          return DataCell(Text(money(e.discount), style: TextStyle(color: e.discount > 0 ? kOwe : null)));
        case 'net':
          return DataCell(Text(money(e.debit), style: TextStyle(fontWeight: FontWeight.bold)));
        case 'method':
          return DataCell(Text(e.credit > 0 ? payMethodLabel(e.payMethod) : 'آجل'));
        case 'status':
          return DataCell(invoiceStatusPill(e.status));
        case 'collect':
          return DataCell(_collect(e));
        case 'rep':
          return DataCell(Text(e.rep.isEmpty ? '—' : e.rep));
        default:
          return DataCell(_actions(e));
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(Color(0xFF111111)),
          headingTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 72,
          columnSpacing: 22,
          columns: [for (final k in keys) DataColumn(label: Text(_cols[k]!))],
          rows: [for (final e in list) DataRow(cells: [for (final k in keys) cell(k, e)])],
        ),
      ),
    );
  }

  Widget _card(Entry e) {
    final live = Live.I;
    final cid = (e.m['customerId'] ?? '').toString();
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => openInvoice(context, e),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(invoiceLabel(e.invoiceNo), style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 8),
              invoiceStatusPill(e.status),
              const Spacer(),
              Text(money(e.debit), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            SizedBox(height: 4),
            Row(children: [
              Expanded(
                  child: Text(live.customerName(cid),
                      overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600))),
              Text(fmtDate(e.date), style: TextStyle(color: kMuted, fontSize: 12)),
            ]),
            Text(
              [
                e.credit > 0 ? payMethodLabel(e.payMethod) : 'آجل',
                if (e.discount > 0) 'خصم ${num2(e.discount)}',
                if (e.rep.isNotEmpty) 'المندوب: ${e.rep}',
              ].join(' · '),
              style: TextStyle(color: kMuted, fontSize: 12),
            ),
            Row(children: [
              Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: _collect(e))),
              _actions(e),
            ]),
          ]),
        ),
      ),
    );
  }
}
