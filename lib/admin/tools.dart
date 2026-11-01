import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core.dart';
import '../pdf.dart';
import 'live.dart';
import 'shell.dart';

// ======================== الإكسل ========================

class ExcelScreen extends StatefulWidget {
  const ExcelScreen({super.key});
  @override
  State<ExcelScreen> createState() => _ExcelScreenState();
}

class _ExcelScreenState extends State<ExcelScreen> {
  bool busy = false;
  String log = '';

  xl.CellValue _v(dynamic v) {
    if (v is num) return xl.DoubleCellValue(v.toDouble());
    return xl.TextCellValue((v ?? '').toString());
  }

  void _sheet(xl.Excel ex, String name, List<String> head, List<List<dynamic>> rows) {
    final s = ex[name];
    s.appendRow(head.map((h) => xl.TextCellValue(h)).toList());
    for (final r in rows) {
      s.appendRow(r.map(_v).toList());
    }
  }

  Future<void> _share(Uint8List bytes, String name) async {
    await Share.shareXFiles([
      XFile.fromData(bytes,
          name: name, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    ], subject: name);
  }

  Future<void> _export(Set<String> what) async {
    setState(() => busy = true);
    try {
      final live = Live.I;
      final ex = xl.Excel.createExcel();
      final first = ex.getDefaultSheet();
      if (what.contains('customers')) {
        _sheet(ex, 'العملاء', ['الكود', 'الاسم', 'الموبايل', 'العنوان', 'المسحوب', 'المدفوع', 'الباقي', 'النقط'], [
          for (final c in live.customers)
            () {
              final m = c.data();
              final a = live.accountOf(c.id);
              return [toI(m['code']), m['name'], m['phone'], m['address'], a.debit, a.paid, a.balance, a.points];
            }()
        ]);
      }
      if (what.contains('products')) {
        _sheet(ex, 'الأصناف', ['الكود', 'الاسم', 'السعر', 'الكمية', if (Me.owner) 'سعر الشرا', 'حد التنبيه'], [
          for (final p in live.products)
            [
              p.data()['code'],
              p.data()['name'],
              toD(p.data()['price']),
              p.data()['stock'] == null ? '' : toD(p.data()['stock']),
              if (Me.owner) live.costOf(p.id),
              toD(p.data()['minStock'] ?? 2),
            ]
        ]);
      }
      if (what.contains('sales')) {
        _sheet(ex, 'المبيعات', ['الرقم', 'التاريخ', 'العميل', 'الإجمالي', 'الخصم', 'الصافي', 'المدفوع', 'الباقي', 'الحالة', 'طريقة الدفع', 'المندوب'], [
          for (final e in live.sales)
            [
              invoiceLabel(e.invoiceNo),
              fmtDate(e.date),
              live.customerName((e.m['customerId'] ?? '').toString()),
              e.gross,
              e.discount,
              e.debit,
              e.debit - e.remaining,
              e.remaining,
              {'paid': 'مسددة', 'deferred': 'آجلة', 'returned': 'مرتجع'}[e.status] ?? '',
              e.credit > 0 ? payMethodLabel(e.payMethod) : 'آجل',
              e.rep,
            ]
        ]);
        _sheet(ex, 'تفاصيل المبيعات', ['الرقم', 'التاريخ', 'العميل', 'الصنف', 'الكود', 'الكمية', 'السعر', 'الإجمالي', 'رجع'], [
          for (final e in live.sales)
            for (final it in e.items)
              [
                invoiceLabel(e.invoiceNo),
                fmtDate(e.date),
                live.customerName((e.m['customerId'] ?? '').toString()),
                it['name'],
                it['code'],
                toD(it['qty']),
                toD(it['price']),
                toD(it['qty']) * toD(it['price']),
                toD(it['returned']),
              ]
        ]);
      }
      if (what.contains('payments')) {
        _sheet(ex, 'التحصيلات', ['التاريخ', 'العميل', 'المبلغ', 'طريقة الدفع', 'سجّلها', 'ملاحظات'], [
          for (final e in live.entries.where((e) => e.kind == 'pay'))
            [fmtDate(e.date), live.customerName((e.m['customerId'] ?? '').toString()), e.credit, payMethodLabel(e.m['method']), e.by, e.note]
        ]);
      }
      if (what.contains('expenses')) {
        _sheet(ex, 'المصروفات', ['التاريخ', 'البند', 'المبلغ', 'طريقة الدفع', 'تفاصيل'], [
          for (final x in live.expenses)
            [fmtDate(x.data()['date']), x.data()['category'], toD(x.data()['amount']), payMethodLabel(x.data()['method']), x.data()['note']]
        ]);
      }
      if (what.contains('purchases')) {
        _sheet(ex, 'المشتريات', ['الرقم', 'التاريخ', 'المورد', 'الإجمالي', 'المدفوع'], [
          for (final p in live.purchases)
            [purchaseLabel(toI(p.data()['no'])), fmtDate(p.data()['date']), p.data()['supplierName'], toD(p.data()['total']), toD(p.data()['paid'])]
        ]);
      }
      if (first != null && ex.sheets.length > 1) ex.delete(first);
      final bytes = ex.encode();
      if (bytes == null) throw 'ماقدرتش أعمل الملف';
      final d = DateTime.now();
      await _share(Uint8List.fromList(bytes), '${Brand.name}-${d.year}-${d.month}-${d.day}.xlsx');
    } catch (e) {
      if (mounted) toast(context, 'حصلت مشكلة: $e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _template() async {
    final ex = xl.Excel.createExcel();
    final first = ex.getDefaultSheet();
    _sheet(ex, 'الأصناف', ['الكود', 'الاسم', 'السعر', 'الكمية', 'سعر الشرا', 'حد التنبيه'], [
      ['P-001', 'كريم مرطب 50 مل', 150, 20, 95, 3],
      ['P-002', 'روج مات', 95, 12, 55, 2],
    ]);
    if (first != null) ex.delete(first);
    final bytes = ex.encode();
    if (bytes != null) await _share(Uint8List.fromList(bytes), 'نموذج-الأصناف.xlsx');
  }

  String _s(xl.Data? d) {
    final v = d?.value;
    if (v == null) return '';
    return v.toString().trim();
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    final bytes = r?.files.first.bytes;
    if (bytes == null) return;
    setState(() {
      busy = true;
      log = '';
    });
    try {
      final ex = xl.Excel.decodeBytes(bytes);
      final table = ex.tables.values.first;
      final rows = table.rows;
      if (rows.length < 2) throw 'الملف فاضي';
      final head = rows.first.map(_s).toList();
      int col(String n) => head.indexWhere((h) => h.contains(n));
      final iCode = col('الكود'), iName = col('الاسم'), iPrice = col('السعر'), iQty = col('الكمية');
      final iCost = col('الشرا'), iMin = col('التنبيه');
      if (iName < 0) throw 'لازم يكون فيه عمود اسمه «الاسم»';
      final live = Live.I;
      var added = 0, updated = 0;
      var batch = db.batch();
      var n = 0;
      for (final row in rows.skip(1)) {
        String at(int i) => i >= 0 && i < row.length ? _s(row[i]) : '';
        final name = at(iName);
        if (name.isEmpty) continue;
        final code = at(iCode);
        final data = <String, dynamic>{'name': name, if (code.isNotEmpty) 'code': code};
        if (at(iPrice).isNotEmpty) data['price'] = toD(at(iPrice));
        if (at(iQty).isNotEmpty) data['stock'] = toD(at(iQty));
        if (at(iMin).isNotEmpty) data['minStock'] = toD(at(iMin));
        Doc? existing;
        for (final p in live.products) {
          if ((code.isNotEmpty && p.data()['code'] == code) || (code.isEmpty && p.data()['name'] == name)) existing = p;
        }
        final ref = existing == null ? db.collection('products').doc() : db.collection('products').doc(existing.id);
        if (existing == null) {
          batch.set(ref, {...data, 'visible': true, 'createdAt': FieldValue.serverTimestamp()});
          added++;
        } else {
          batch.update(ref, data);
          updated++;
        }
        if (Me.owner && at(iCost).isNotEmpty) batch.set(db.collection('productCosts').doc(ref.id), {'cost': toD(at(iCost))});
        if (++n % 200 == 0) {
          await batch.commit();
          batch = db.batch();
        }
      }
      await batch.commit();
      setState(() => log = 'اتضاف $added صنف جديد، واتحدّث $updated صنف.');
    } catch (e) {
      setState(() => log = 'حصلت مشكلة: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final options = <String, String>{
      'customers': 'العملاء وأرصدتهم',
      'products': 'الأصناف والمخزون',
      'sales': 'المبيعات وتفاصيلها',
      'payments': 'التحصيلات',
      if (Me.can('expenses')) 'expenses': 'المصروفات',
      if (Me.can('purchases')) 'purchases': 'المشتريات',
    };
    return Scaffold(
      appBar: pageAppBar(context, 'الإكسل'),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 760),
          child: ListView(padding: EdgeInsets.all(14), children: [
            if (busy) LinearProgressIndicator(),
            Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('تصدير لملف Excel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 4),
                  Text('ملف واحد فيه شيت لكل حاجة، تفتحه على Excel أو Google Sheets.', style: TextStyle(color: kMuted)),
                  SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                      onPressed: busy ? null : () => _export(options.keys.toSet()),
                      icon: Icon(Icons.download),
                      label: Text('صدّر كل حاجة'),
                    ),
                    for (final o in options.entries)
                      OutlinedButton(onPressed: busy ? null : () => _export({o.key}), child: Text(o.value)),
                  ]),
                ]),
              ),
            ),
            if (Me.can('products'))
              Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('استيراد الأصناف من Excel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 4),
                    Text(
                        'الأعمدة: الكود، الاسم، السعر، الكمية، سعر الشرا، حد التنبيه. '
                        'الصنف اللي كوده موجود بيتحدّث، والجديد بيتضاف.',
                        style: TextStyle(color: kMuted)),
                    SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                          onPressed: busy ? null : _import,
                          icon: Icon(Icons.upload_file),
                          label: Text('اختار ملف Excel')),
                      OutlinedButton.icon(
                          onPressed: busy ? null : _template,
                          icon: Icon(Icons.description_outlined),
                          label: Text('نزّل نموذج فاضي')),
                    ]),
                    if (log.isNotEmpty) ...[SizedBox(height: 10), Text(log, style: TextStyle(fontWeight: FontWeight.bold))],
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ======================== مصمم الفاتورة ========================

class InvoiceDesigner extends StatefulWidget {
  const InvoiceDesigner({super.key});
  @override
  State<InvoiceDesigner> createState() => _InvoiceDesignerState();
}

class _InvoiceDesignerState extends State<InvoiceDesigner> {
  late StoreSettings st = Live.I.settings;
  late final header = TextEditingController(text: st.header);
  late final footer = TextEditingController(text: st.footer);
  int version = 0;
  bool busy = false;

  void _set(Map<String, dynamic> c) => setState(() {
        st = st.copyWith(c);
        version++;
      });

  Entry get _sample => Entry('sample', {
        'kind': 'sale',
        'date': DateTime.now(),
        'invoiceNo': 36,
        'items': [
          {'name': 'كريم مرطب 50 مل', 'code': 'P-004', 'qty': 2, 'price': 150, 'paid': 300},
          {'name': 'روج مات', 'code': 'P-011', 'qty': 1, 'price': 95, 'paid': 0},
        ],
        'discount': 5,
        'debit': 390,
        'credit': 300,
        'payMethod': 'cash',
        'rep': 'أحمد',
        'note': 'هتدفع الباقي أول الشهر',
      });

  @override
  Widget build(BuildContext context) {
    final controls = ListView(padding: EdgeInsets.all(14), children: [
      Text('مقاس الورق', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height: 6),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'a4', label: Text('A4')),
          ButtonSegment(value: 'a5', label: Text('A5')),
          ButtonSegment(value: 'roll', label: Text('رول كاشير 80مم')),
        ],
        selected: {st.paper},
        onSelectionChanged: (s) => _set({'paper': s.first}),
      ),
      SizedBox(height: 8),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: st.showLogo,
          title: Text('اللوجو'),
          onChanged: (v) => _set({'showLogo': v})),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: st.showStoreInfo,
          title: Text('عنوان وتليفون المحل'),
          onChanged: (v) => _set({'showStoreInfo': v})),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: st.showCodes,
          title: Text('أكواد الأصناف'),
          onChanged: (v) => _set({'showCodes': v})),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: st.showBalance,
          title: Text('إجمالي حساب العميل'),
          onChanged: (v) => _set({'showBalance': v})),
      SizedBox(height: 8),
      TextField(
        controller: header,
        decoration: InputDecoration(labelText: 'كلام فوق الفاتورة (اختياري)'),
        onSubmitted: (v) => _set({'header': v}),
        onEditingComplete: () => _set({'header': header.text}),
      ),
      SizedBox(height: 10),
      TextField(
        controller: footer,
        decoration: InputDecoration(labelText: 'كلام تحت الفاتورة'),
        onSubmitted: (v) => _set({'footer': v}),
        onEditingComplete: () => _set({'footer': footer.text}),
      ),
      SizedBox(height: 16),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                st = st.copyWith({'header': header.text.trim(), 'footer': footer.text.trim()});
                await settingsRef.set(st.toMap(), SetOptions(merge: true));
                if (!mounted) return;
                setState(() => busy = false);
                toast(context, 'اتحفظ شكل الفاتورة');
              },
        style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
        child: Text('حفظ'),
      ),
      SizedBox(height: 6),
      OutlinedButton(onPressed: () => _set({'header': header.text, 'footer': footer.text}), child: Text('حدّث المعاينة')),
    ]);
    final preview = Container(
      color: kBlush,
      child: PdfPreview(
        key: ValueKey(version),
        build: (_) => buildInvoice({'name': 'مدام سعاد', 'phone': '01012345678', 'code': 12}, _sample, st, balance: 545),
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        pdfFileName: 'معاينة.pdf',
      ),
    );
    return Scaffold(
      appBar: pageAppBar(context, 'مصمم الفاتورة'),
      body: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 900
            ? Row(children: [SizedBox(width: 380, child: controls), Expanded(child: preview)])
            : Column(children: [Expanded(child: controls), SizedBox(height: 420, child: preview)]),
      ),
    );
  }
}

// ======================== هوية نشاطي ========================

class BrandScreen extends StatefulWidget {
  const BrandScreen({super.key});
  @override
  State<BrandScreen> createState() => _BrandScreenState();
}

class _BrandScreenState extends State<BrandScreen> {
  late final st = Live.I.settings;
  late final name = TextEditingController(text: st.storeName);
  late final slogan = TextEditingController(text: st.slogan);
  late final phone = TextEditingController(text: st.storePhone);
  late final whatsapp = TextEditingController(text: st.whatsapp);
  late final address = TextEditingController(text: st.storeAddress);
  late String logo = st.logo;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageAppBar(context, 'هوية نشاطي'),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640),
          child: ListView(padding: EdgeInsets.all(16), children: [
            Card(
              color: kSide,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: Colors.white,
                      width: 72,
                      height: 72,
                      child: logo.isNotEmpty
                          ? B64Image(logo, fit: BoxFit.contain)
                          : Image.asset('assets/icon.png', fit: BoxFit.cover),
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name.text.isEmpty ? kStoreName : name.text,
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(slogan.text, style: TextStyle(color: Color(0xFFBDBDBD))),
                    ]),
                  ),
                ]),
              ),
            ),
            SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final b = await pickImageB64(context, maxWidth: 500);
                  if (b != null) setState(() => logo = b);
                },
                icon: Icon(Icons.image_outlined),
                label: Text('غيّر اللوجو'),
              ),
              if (logo.isNotEmpty)
                TextButton(onPressed: () => setState(() => logo = ''), child: Text('رجّع اللوجو الأصلي')),
            ]),
            SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: InputDecoration(labelText: 'اسم النشاط'),
                onChanged: (_) => setState(() {})),
            SizedBox(height: 10),
            TextField(
                controller: slogan,
                decoration: InputDecoration(labelText: 'الشعار (الجملة اللي تحت الاسم)'),
                onChanged: (_) => setState(() {})),
            SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'تليفون المحل')),
            SizedBox(height: 10),
            TextField(controller: whatsapp, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'واتساب المحل')),
            SizedBox(height: 10),
            TextField(controller: address, decoration: InputDecoration(labelText: 'العنوان')),
            SizedBox(height: 8),
            Text('الاسم واللوجو بيظهروا في القايمة والفواتير والسندات وكشوف الحساب.', style: TextStyle(color: kMuted, fontSize: 12.5)),
            SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await settingsRef.set({
                        'storeName': name.text.trim(),
                        'slogan': slogan.text.trim(),
                        'storePhone': phone.text.trim(),
                        'whatsapp': whatsapp.text.trim(),
                        'storeAddress': address.text.trim(),
                        'logo': logo,
                      }, SetOptions(merge: true));
                      if (!mounted) return;
                      setState(() => busy = false);
                      toast(context, 'اتحفظت هوية النشاط');
                    },
              style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
              child: Text('حفظ'),
            ),
          ]),
        ),
      ),
    );
  }
}
