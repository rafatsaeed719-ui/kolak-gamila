import 'dart:typed_data';

import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'core.dart';

const _plum = PdfColor(0.478, 0.122, 0.278);
const _blush = PdfColor(0.973, 0.933, 0.945);
const _ink = PdfColor(0.165, 0.106, 0.133);
const _grey = PdfColor(0.49, 0.4, 0.44);
const _line = PdfColor(0.92, 0.87, 0.89);
const _red = PdfColor(0.706, 0.137, 0.184);
const _green = PdfColor(0.114, 0.478, 0.322);

pw.Font? _regular, _bold;
pw.MemoryImage? _logo;

Future<void> _load() async {
  _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
  _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
  _logo ??= pw.MemoryImage((await rootBundle.load('assets/icon.png')).buffer.asUint8List());
}

/// للاختبار من برّه التطبيق
void setPdfAssets(pw.Font regular, pw.Font bold, pw.MemoryImage logo) {
  _regular = regular;
  _bold = bold;
  _logo = logo;
}

pw.Widget _t(String s,
        {double size = 11, bool bold = false, PdfColor color = _ink, pw.TextAlign align = pw.TextAlign.right}) =>
    pw.Text(s,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(font: bold ? _bold : _regular, fontSize: size, color: color));

pw.Widget _header(String title, String sub, StoreSettings st) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(color: _blush, borderRadius: pw.BorderRadius.circular(10)),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _t(kStoreName, size: 22, bold: true, color: _plum),
          if (st.storePhone.isNotEmpty || st.storeAddress.isNotEmpty)
            _t([st.storeAddress, st.storePhone].where((e) => e.isNotEmpty).join('  ·  '), size: 10, color: _grey),
          pw.SizedBox(height: 6),
          _t(title, size: 15, bold: true),
          _t(sub, size: 10, color: _grey),
        ]),
      ),
      pw.SizedBox(width: 12),
      if (_logo != null) pw.ClipRRect(horizontalRadius: 12, verticalRadius: 12, child: pw.Image(_logo!, width: 64, height: 64)),
    ]),
  );
}

pw.Widget _cell(String s, {bool head = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.right}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: _t(s, size: head ? 10 : 11, bold: head, color: color ?? (head ? _plum : _ink), align: align),
    );

pw.Widget _row(String a, String b, {bool bold = false, PdfColor color = _ink}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(children: [
        _t(b, bold: bold, color: color),
        pw.Spacer(),
        _t(a, bold: bold, color: color),
      ]),
    );

Future<Uint8List> buildInvoice(Map<String, dynamic> customer, Entry e, StoreSettings st, {double? balance}) async {
  await _load();
  final doc = pw.Document();
  final items = e.items;
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(22),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      _header('فاتورة رقم ${e.invoiceNo > 0 ? e.invoiceNo : '-'}', fmtDate(e.date, time: true), st),
      pw.SizedBox(height: 10),
      _row('العميل', '${customer['name'] ?? ''}  (#${pad4(customer['code'])})', bold: true),
      if ((customer['phone'] ?? '').toString().isNotEmpty) _row('الموبايل', customer['phone'].toString()),
      pw.SizedBox(height: 8),
      if (items.isNotEmpty)
        pw.Table(
          border: pw.TableBorder(horizontalInside: const pw.BorderSide(color: _line, width: .6)),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(1.3),
            3: const pw.FlexColumnWidth(4),
          },
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: _blush), children: [
              _cell('الإجمالي', head: true, align: pw.TextAlign.left),
              _cell('السعر', head: true, align: pw.TextAlign.left),
              _cell('الكمية', head: true, align: pw.TextAlign.center),
              _cell('الصنف', head: true),
            ]),
            ...items.map((it) => pw.TableRow(children: [
                  _cell(num2(toD(it['qty']) * toD(it['price'])), align: pw.TextAlign.left),
                  _cell(num2(it['price']), align: pw.TextAlign.left),
                  _cell(num2(it['qty']), align: pw.TextAlign.center),
                  _cell('${it['name']}${(it['code'] ?? '').toString().isEmpty ? '' : '  ${it['code']}'}'),
                ])),
          ],
        ),
      pw.SizedBox(height: 10),
      if (toD(e.m['extra']) > 0) _row('مديونية إضافية', money(e.m['extra'])),
      _row('إجمالي الفاتورة', money(e.debit), bold: true),
      if (e.credit > 0) _row('المدفوع', money(e.credit), color: _green),
      _row('باقي الفاتورة', money(e.debit - e.credit), bold: true, color: _red),
      if (balance != null) ...[
        pw.Divider(color: _line),
        _row('إجمالي الحساب المتبقي', money(balance), bold: true, color: balance > 0 ? _red : _green),
      ],
      if (e.note.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _t('ملاحظات: ${e.note}', size: 10, color: _grey),
      ],
      pw.Spacer(),
      pw.Center(child: _t('شكراً لتعاملك مع $kStoreName', size: 11, color: _plum)),
    ]),
  ));
  return doc.save();
}

Future<Uint8List> buildStatement(Map<String, dynamic> customer, Account acc, StoreSettings st) async {
  await _load();
  final doc = pw.Document();
  final entries = [...acc.entries]..sort((a, b) => a.date.compareTo(b.date));
  var run = 0.0;
  final rows = <pw.TableRow>[];
  for (final e in entries) {
    run += e.debit - e.credit;
    final what = switch (e.kind) {
      'pay' => 'دفعة',
      'adjust' => e.debit > 0 ? 'زيادة: ${e.note}' : 'خصم: ${e.note}',
      'redeem' => 'استبدال نقط',
      _ => e.items.isEmpty
          ? (e.note.isEmpty ? 'مديونية' : e.note)
          : '${e.invoiceNo > 0 ? 'فاتورة ${e.invoiceNo}: ' : ''}${e.items.map((i) => i['name']).join('، ')}',
    };
    rows.add(pw.TableRow(children: [
      _cell(num2(run), align: pw.TextAlign.left),
      _cell(e.credit > 0 ? num2(e.credit) : '', color: _green, align: pw.TextAlign.left),
      _cell(e.debit > 0 ? num2(e.debit) : '', color: _red, align: pw.TextAlign.left),
      _cell(what),
      _cell(fmtDate(e.date)),
    ]));
  }
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => [
      _header('كشف حساب', 'بتاريخ ${fmtDate(DateTime.now())}', st),
      pw.SizedBox(height: 10),
      _row('العميل', '${customer['name'] ?? ''}  (#${pad4(customer['code'])})', bold: true),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder(horizontalInside: const pw.BorderSide(color: _line, width: .6)),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.4),
          1: const pw.FlexColumnWidth(1.4),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(5),
          4: const pw.FlexColumnWidth(1.8),
        },
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: _blush), children: [
            _cell('الرصيد', head: true, align: pw.TextAlign.left),
            _cell('دفع', head: true, align: pw.TextAlign.left),
            _cell('عليه', head: true, align: pw.TextAlign.left),
            _cell('البيان', head: true),
            _cell('التاريخ', head: true),
          ]),
          ...rows,
        ],
      ),
      pw.SizedBox(height: 12),
      _row('إجمالي المسحوب', money(acc.debit)),
      _row('إجمالي المدفوع', money(acc.paid), color: _green),
      if (acc.discounts > 0.004) _row('خصومات', money(acc.discounts)),
      _row('المتبقي', money(acc.balance), bold: true, color: acc.balance > 0 ? _red : _green),
      _row('النقط', '${acc.points}'),
    ],
  ));
  return doc.save();
}

Future<void> shareInvoicePdf(BuildContext context, Map<String, dynamic> customer, Entry e) async {
  try {
    final st = StoreSettings.fromMap((await settingsRef.get()).data());
    final bytes = await buildInvoice(customer, e, st);
    await Printing.sharePdf(bytes: bytes, filename: 'فاتورة-${e.invoiceNo}-${customer['name'] ?? ''}.pdf');
  } catch (err) {
    if (context.mounted) toast(context, 'ماقدرتش أعمل الفاتورة: ${authError(err)}', error: true);
  }
}

Future<void> shareStatementPdf(BuildContext context, Map<String, dynamic> customer, Account acc) async {
  try {
    final bytes = await buildStatement(customer, acc, acc.settings);
    await Printing.sharePdf(bytes: bytes, filename: 'كشف-حساب-${customer['name'] ?? ''}.pdf');
  } catch (err) {
    if (context.mounted) toast(context, 'ماقدرتش أعمل الكشف: ${authError(err)}', error: true);
  }
}
