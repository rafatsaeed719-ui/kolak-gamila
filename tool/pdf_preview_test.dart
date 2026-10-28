// بيولّد فاتورة وكشف حساب تجريبيين PDF عشان نشوف شكلهم (بيشتغل في البناء بس)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gamila/core.dart';
import 'package:gamila/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('sample pdfs', () async {
    pw.Font f(String p) => pw.Font.ttf(File(p).readAsBytesSync().buffer.asByteData());
    setPdfAssets(f('assets/fonts/Amiri-Regular.ttf'), f('assets/fonts/Amiri-Bold.ttf'),
        pw.MemoryImage(File('assets/icon.png').readAsBytesSync()));
    final now = DateTime(2026, 10, 28, 13, 30);
    final customer = <String, dynamic>{'name': 'مدام سعاد', 'phone': '01012345678', 'code': 12};
    final sale = Entry('s1', {
      'kind': 'sale',
      'date': now,
      'invoiceNo': 41,
      'items': [
        {'name': 'كريم مرطب 50 مل', 'code': 'P-004', 'qty': 2, 'price': 150, 'paid': 300},
        {'name': 'روج مات', 'code': 'P-011', 'qty': 1, 'price': 95, 'paid': 0},
      ],
      'extra': 0,
      'debit': 395,
      'credit': 300,
      'note': 'هتدفع الباقي أول الشهر',
    });
    const st = Settings(storePhone: '01000000000', storeAddress: 'شارع الجمهورية');
    File('invoice-sample.pdf').writeAsBytesSync(await buildInvoice(customer, sale, st, balance: 545));
    final pay = Entry('p1', {'kind': 'pay', 'date': now.add(const Duration(days: 3)), 'debit': 0, 'credit': 250});
    final old = Entry('a1', {'kind': 'adjust', 'date': now.subtract(const Duration(days: 20)), 'debit': 400, 'credit': 0, 'note': 'مديونية سابقة'});
    File('statement-sample.pdf').writeAsBytesSync(await buildStatement(customer, Account([sale, pay, old], st), st));
  });
}
