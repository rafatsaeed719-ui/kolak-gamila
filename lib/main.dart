import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'admin/admin_home.dart';
import 'core.dart';
import 'customer/customer_home.dart';
import 'firebase_options.dart';
import 'login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: kgFirebaseOptions);
  runApp(const KolakGamilaApp());
}

class KolakGamilaApp extends StatelessWidget {
  const KolakGamilaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kPlum, primary: kPlum, secondary: kRose);
    return MaterialApp(
      title: kStoreName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAF5F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: kPlum,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFEBDDE2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Loading());
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        if (isAdmin) {
          Me.owner = true;
          Me.name = 'صاحب المحل';
          Me.perms = kPerms.keys.toSet();
          return const AdminHome(key: ValueKey('owner'));
        }
        // الدخول بالإيميل لصاحب المحل بس
        if (!(user.email ?? '').endsWith('@$kUserDomain')) return const _NotAllowed();
        return UserGate(key: ValueKey(user.uid));
      },
    );
  }
}

class _NotAllowed extends StatelessWidget {
  const _NotAllowed();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: const EmptyView('الدخول بالإيميل لصاحب المحل بس',
            text: 'العملاء والموظفين بيدخلوا برقم الموبايل.', icon: Icons.lock_outline),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(onPressed: () => auth.signOut(), child: const Text('رجوع')),
          ),
        ),
      );
}

/// اللي داخل برقم موبايل: موظف ولا عميل
class UserGate extends StatelessWidget {
  const UserGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Loading());
        final me = snap.data!.data();
        if (me == null) return const CompleteProfile();
        if (me['disabled'] == true) {
          return Scaffold(
            body: const EmptyView('الحساب ده موقوف',
                text: 'كلّم المحل عشان يفعّله تاني.', icon: Icons.lock_outline),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(onPressed: () => auth.signOut(), child: const Text('خروج')),
              ),
            ),
          );
        }
        if (me['role'] == 'staff') {
          Me.owner = false;
          Me.name = (me['name'] ?? '').toString();
          Me.perms = ((me['perms'] as List?) ?? []).map((e) => e.toString()).toSet();
          return const AdminHome(key: ValueKey('staff'));
        }
        return CustomerHome(me: me);
      },
    );
  }
}
