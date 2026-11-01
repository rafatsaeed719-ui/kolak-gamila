import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'core.dart';

// أبيض وأسود زي اللوجو
const _black = PdfColor(0.07, 0.07, 0.07);
const _soft = PdfColor(0.95, 0.95, 0.94);
const _ink = PdfColor(0.1, 0.1, 0.1);
const _grey = PdfColor(0.42, 0.42, 0.4);
const _line = PdfColor(0.88, 0.88, 0.86);
const _red = PdfColor(0.7, 0.15, 0.12);
const _green = PdfColor(0.12, 0.48, 0.31);

pw.Font? _regular, _bold;
pw.MemoryImage? _logo;

Future<void> _load() async {
  _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
  _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
  _logo ??= pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
}

/// للاختبار من برّه التطبيق
void setPdfAssets(pw.Font regular, pw.Font bold, pw.MemoryImage logo) {
  _regular = regular;
  _bold = bold;
  _logo = logo;
}

pw.ImageProvider? _brandLogo(StoreSettings st) {
  if (st.logo.isNotEmpty) {
    try {
      return pw.MemoryImage(base64Decode(st.logo));
    } catch (_) {}
  }
  return _logo;
}

PdfPageFormat _format(StoreSettings st) {
  switch (st.paper) {
    case 'a4':
      return PdfPageFormat.a4;
    case 'roll':
      return PdfPageFormat.roll80;
  }
  return PdfPageFormat.a5;
}

pw.Widget _t(String s,
        {double size = 11, bool bold = false, PdfColor color = _ink, pw.TextAlign align = pw.TextAlign.right}) =>
    pw.Text(s,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(font: bold ? _bold : _regular, fontSize: size, color: color));

pw.Widget _header(String title, String sub, StoreSettings st, {bool small = false}) {
  final logo = st.showLogo ? _brandLogo(st) : null;
  return pw.Container(
    padding: pw.EdgeInsets.all(small ? 6 : 12),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _black, width: small ? 1 : 2)),
    ),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _t(st.storeName, size: small ? 15 : 22, bold: true, color: _black),
          if (st.slogan.isNotEmpty && !small) _t(st.slogan, size: 10, color: _grey),
          if (st.showStoreInfo && (st.storePhone.isNotEmpty || st.storeAddress.isNotEmpty))
            _t([st.storeAddress, st.storePhone].where((e) => e.isNotEmpty).join('  ·  '), size: small ? 8 : 10, color: _grey),
          pw.SizedBox(height: 6),
          _t(title, size: small ? 12 : 15, bold: true),
          _t(sub, size: small ? 8 : 10, color: _grey),
        ]),
      ),
      if (logo != null) ...[
        pw.SizedBox(width: 10),
        pw.Image(logo, width: small ? 46 : 72, height: small ? 46 : 72, fit: pw.BoxFit.contain),
      ],
    ]),
  );
}

pw.Widget _cell(String s, {bool head = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.right, double size = 11}) =>
    pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: _t(s, size: head ? size - 1 : size, bold: head, color: color ?? (head ? PdfColors.white : _ink), align: align),
    );

pw.Widget _row(String a, String b, {bool bold = false, PdfColor color = _ink, double size = 11}) => pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(children: [
        _t(b, bold: bold, color: color, size: size),
        pw.Spacer(),
        _t(a, bold: bold, color: color, size: size),
      ]),
    );

Future<Uint8List> buildInvoice(Map<String, dynamic> customer, Entry e, StoreSettings st, {double? balance}) async {
  await _load();
  final doc = pw.Document();
  final items = e.items;
  final small = st.paper == 'roll';
  final fs = small ? 9.0 : 11.0;
  final isCash = toI(customer['code']) == 0;
  final body = <pw.Widget>[
    _header('فاتورة بيع ${invoiceLabel(e.invoiceNo)}', fmtDate(e.date, time: true), st, small: small),
    if (st.header.isNotEmpty) ...[pw.SizedBox(height: 6), _t(st.header, size: fs, color: _grey)],
    pw.SizedBox(height: 8),
    _row('العميل', isCash ? 'نقدي' : '${customer['name'] ?? ''}  (#${pad4(customer['code'])})', bold: true, size: fs),
    if (!isCash && (customer['phone'] ?? '').toString().isNotEmpty) _row('الموبايل', customer['phone'].toString(), size: fs),
    _row('طريقة الدفع', e.credit > 0 ? payMethodLabel(e.payMethod) : 'آجل', size: fs),
    if (e.rep.isNotEmpty) _row('المندوب', e.rep, size: fs),
    pw.SizedBox(height: 8),
    if (items.isNotEmpty)
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: .6)),
        columnWidths: {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(1.8),
          2: pw.FlexColumnWidth(1.2),
          3: pw.FlexColumnWidth(4),
        },
        children: [
          pw.TableRow(decoration: pw.BoxDecoration(color: _black), children: [
            _cell('الإجمالي', head: true, align: pw.TextAlign.left, size: fs),
            _cell('السعر', head: true, align: pw.TextAlign.left, size: fs),
            _cell('الكمية', head: true, align: pw.TextAlign.center, size: fs),
            _cell('الصنف', head: true, size: fs),
          ]),
          ...items.map((it) => pw.TableRow(children: [
                _cell(num2(toD(it['qty']) * toD(it['price'])), align: pw.TextAlign.left, size: fs),
                _cell(num2(it['price']), align: pw.TextAlign.left, size: fs),
                _cell(num2(it['qty']), align: pw.TextAlign.center, size: fs),
                _cell('${it['name']}${st.showCodes && (it['code'] ?? '').toString().isNotEmpty ? '  ${it['code']}' : ''}'
                    '${toD(it['returned']) > 0 ? '  (رجع ${num2(it['returned'])})' : ''}', size: fs),
              ])),
        ],
      ),
    pw.SizedBox(height: 10),
    if (e.extra > 0) _row('مديونية إضافية', money(e.extra), size: fs),
    _row('الإجمالي', money(e.gross), size: fs),
    if (e.discount > 0) _row('الخصم', '- ${money(e.discount)}', color: _red, size: fs),
    _row('الصافي', money(e.debit), bold: true, size: fs + 1),
    if (e.credit > 0) _row('المدفوع', money(e.credit), color: _green, size: fs),
    _row('الباقي على الفاتورة', money(e.remaining), bold: true, color: e.remaining > 0 ? _red : _green, size: fs),
    if (balance != null && st.showBalance && !isCash) ...[
      pw.Divider(color: _line),
      _row('إجمالي الحساب المتبقي', money(balance), bold: true, color: balance > 0 ? _red : _green, size: fs),
    ],
    if (e.note.isNotEmpty) ...[pw.SizedBox(height: 8), _t('ملاحظات: ${e.note}', size: fs - 1, color: _grey)],
    pw.SizedBox(height: 14),
    if (st.footer.isNotEmpty) pw.Center(child: _t(st.footer, size: fs, color: _black)),
  ];
  if (small) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: pw.EdgeInsets.all(6),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: body),
    ));
  } else {
    doc.addPage(pw.MultiPage(
      pageFormat: _format(st),
      margin: pw.EdgeInsets.all(22),
      textDirection: pw.TextDirection.rtl,
      build: (_) => body,
    ));
  }
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
      'pay' => 'دفعة (${payMethodLabel(e.m['method'])})',
      'adjust' => e.debit > 0 ? 'زيادة: ${e.note}' : 'خصم: ${e.note}',
      'redeem' => 'استبدال نقط',
      'return' => 'مرتجع من ${invoiceLabel(toI(e.m['saleNo']))}',
      _ => e.items.isEmpty
          ? (e.note.isEmpty ? 'مديونية' : e.note)
          : '${invoiceLabel(e.invoiceNo)}: ${e.items.map((i) => i['name']).join('، ')}',
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
    margin: pw.EdgeInsets.all(28),
    build: (_) => [
      _header('كشف حساب', 'بتاريخ ${fmtDate(DateTime.now())}', st),
      pw.SizedBox(height: 10),
      _row('العميل', '${customer['name'] ?? ''}  (#${pad4(customer['code'])})', bold: true),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: .6)),
        columnWidths: {
          0: pw.FlexColumnWidth(1.4),
          1: pw.FlexColumnWidth(1.4),
          2: pw.FlexColumnWidth(1.4),
          3: pw.FlexColumnWidth(5),
          4: pw.FlexColumnWidth(1.8),
        },
        children: [
          pw.TableRow(decoration: pw.BoxDecoration(color: _black), children: [
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
      if (acc.returns > 0.004) _row('المرتجعات', money(acc.returns)),
      if (acc.discounts - acc.returns > 0.004) _row('خصومات', money(acc.discounts - acc.returns)),
      _row('المتبقي', money(acc.balance), bold: true, color: acc.balance > 0 ? _red : _green),
      _row('النقط', '${acc.points}'),
    ],
  ));
  return doc.save();
}

/// سند تحصيل أو صرف
Future<Uint8List> buildVoucher({
  required String title,
  required String no,
  required String party,
  required double amount,
  required String method,
  required String note,
  required DateTime date,
  required StoreSettings st,
  double? balance,
}) async {
  await _load();
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5.landscape,
    margin: pw.EdgeInsets.all(22),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      _header('$title $no', fmtDate(date, time: true), st),
      pw.SizedBox(height: 14),
      _row(title == 'سند صرف' ? 'اتصرف إلى' : 'استلمنا من', party, bold: true, size: 13),
      _row('مبلغ وقدره', money(amount), bold: true, size: 16),
      _row('طريقة الدفع', method),
      if (note.isNotEmpty) _row('البيان', note),
      if (balance != null) _row('الباقي على الحساب', money(balance), color: balance > 0 ? _red : _green),
      pw.Spacer(),
      pw.Row(children: [
        _t('توقيع المستلم: ..................', color: _grey),
        pw.Spacer(),
        _t('توقيع المسؤول: ..................', color: _grey),
      ]),
    ]),
  ));
  return doc.save();
}

Future<StoreSettings> _settings() async => StoreSettings.fromMap((await settingsRef.get()).data());

Future<void> shareInvoicePdf(BuildContext context, Map<String, dynamic> customer, Entry e, {double? balance}) async {
  try {
    final bytes = await buildInvoice(customer, e, await _settings(), balance: balance);
    await Printing.sharePdf(bytes: bytes, filename: '${invoiceLabel(e.invoiceNo)}-${customer['name'] ?? ''}.pdf');
  } catch (err) {
    if (context.mounted) toast(context, 'ماقدرتش أعمل الفاتورة: ${authError(err)}', error: true);
  }
}

Future<void> shareStatementPdf(BuildContext context, Map<String, dynamic> customer, Account acc) async {
  try {
    final bytes = await buildStatement(customer, acc, await _settings());
    await Printing.sharePdf(bytes: bytes, filename: 'كشف-حساب-${customer['name'] ?? ''}.pdf');
  } catch (err) {
    if (context.mounted) toast(context, 'ماقدرتش أعمل الكشف: ${authError(err)}', error: true);
  }
}

Future<void> shareVoucherPdf(BuildContext context,
    {required String title,
    required String no,
    required String party,
    required double amount,
    required String method,
    required String note,
    required DateTime date,
    double? balance}) async {
  try {
    final bytes = await buildVoucher(
        title: title,
        no: no,
        party: party,
        amount: amount,
        method: method,
        note: note,
        date: date,
        st: await _settings(),
        balance: balance);
    await Printing.sharePdf(bytes: bytes, filename: '$title-$no.pdf');
  } catch (err) {
    if (context.mounted) toast(context, 'ماقدرتش أعمل السند: ${authError(err)}', error: true);
  }
}
