import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core.dart';
import 'live.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final s = Live.I.settings;
  late final threshold = TextEditingController(text: num2(s.pointThreshold).replaceAll(',', ''));
  late final phone = TextEditingController(text: s.storePhone);
  late final address = TextEditingController(text: s.storeAddress);
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('النقط', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPlum)),
        const SizedBox(height: 8),
        numField(threshold, 'المبلغ اللي بيدّي نقطة (ج)', onChanged: (_) => setState(() {})),
        const SizedBox(height: 6),
        Text(StoreSettings(pointThreshold: toD(threshold.text) <= 0 ? 200 : toD(threshold.text)).rulesText,
            style: const TextStyle(color: kMuted)),
        const SizedBox(height: 20),
        const Text('بيانات المحل في الفواتير',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPlum)),
        const SizedBox(height: 8),
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'تليفون المحل')),
        const SizedBox(height: 10),
        TextField(controller: address, decoration: const InputDecoration(labelText: 'عنوان المحل')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  final nav = Navigator.of(context);
                  await settingsRef.set(
                      StoreSettings(
                        pointThreshold: toD(threshold.text) <= 0 ? 200 : toD(threshold.text),
                        storePhone: phone.text.trim(),
                        storeAddress: address.text.trim(),
                      ).toMap(),
                      SetOptions(merge: true));
                  nav.pop();
                },
          child: const Text('حفظ'),
        ),
      ]),
    );
  }
}
