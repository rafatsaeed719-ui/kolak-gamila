import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core.dart';
import 'live.dart';
import 'shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final s = Live.I.settings;
  late final threshold = TextEditingController(text: num2(s.pointThreshold).replaceAll(',', ''));
  late final List<String> cats = [...s.expenseCats];
  final newCat = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final hasPin = (AppLock.pin ?? '').isNotEmpty;
    return Scaffold(
      appBar: pageAppBar(context, 'الإعدادات'),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640),
          child: ListView(padding: EdgeInsets.all(16), children: [
            Text('النقط', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 8),
            numField(threshold, 'المبلغ اللي بيدّي نقطة (ج)', onChanged: (_) => setState(() {})),
            SizedBox(height: 6),
            Text(StoreSettings(pointThreshold: toD(threshold.text) <= 0 ? 200 : toD(threshold.text)).rulesText,
                style: TextStyle(color: kMuted)),
            SizedBox(height: 20),
            Text('بنود المصروفات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in cats) InputChip(label: Text(c), onDeleted: cats.length <= 1 ? null : () => setState(() => cats.remove(c))),
            ]),
            SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: newCat, decoration: InputDecoration(labelText: 'بند جديد'))),
              IconButton(
                icon: Icon(Icons.add),
                onPressed: () {
                  final v = newCat.text.trim();
                  if (v.isNotEmpty && !cats.contains(v)) setState(() => cats.add(v));
                  newCat.clear();
                },
              ),
            ]),
            SizedBox(height: 20),
            Text('قفل البرنامج على الجهاز ده', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.pin_outlined),
              title: Text(hasPin ? 'غيّر رمز القفل' : 'اعمل رمز قفل'),
              onTap: () async {
                await AppLock.askNewPin(context);
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: AppLock.onOpen,
              title: Text('اطلب الرمز كل ما البرنامج يتفتح'),
              onChanged: !hasPin
                  ? null
                  : (v) => setState(() => AppPrefs.setStr('lockOnOpen', v ? '1' : null)),
            ),
            if (hasPin)
              TextButton(
                onPressed: () => setState(() {
                  AppPrefs.setStr('pin', null);
                  AppPrefs.setStr('lockOnOpen', null);
                }),
                child: Text('شيل رمز القفل'),
              ),
            SizedBox(height: 20),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await settingsRef.set({
                        'pointThreshold': toD(threshold.text) <= 0 ? 200 : toD(threshold.text),
                        'expenseCats': cats,
                      }, SetOptions(merge: true));
                      if (!mounted) return;
                      setState(() => busy = false);
                      toast(context, 'اتحفظت الإعدادات');
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
