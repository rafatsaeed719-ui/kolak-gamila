import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'admin/shell.dart';
import 'core.dart';
import 'customer/customer_home.dart';
import 'firebase_options.dart';
import 'login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.load();
  await Firebase.initializeApp(options: kgFirebaseOptions);
  runApp(KolakGamilaApp());
}

ThemeData buildTheme() {
  final dark = AppPrefs.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Color(0xFF111111),
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: kInk,
    onPrimary: kOnInk,
    secondary: kInk,
    onSecondary: kOnInk,
    surface: kSurface,
    onSurface: kInk,
    error: kOwe,
    secondaryContainer: kBlush,
    onSecondaryContainer: kInk,
    primaryContainer: kBlush,
    onPrimaryContainer: kInk,
    surfaceContainerHighest: kBlush,
    outline: kLine,
  );
  final radius = BorderRadius.circular(12);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Plex',
    scaffoldBackgroundColor: kBg,
    dividerColor: kLine,
    appBarTheme: AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: kInk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Plex', fontSize: 19, fontWeight: FontWeight.bold, color: kInk),
      shape: Border(bottom: BorderSide(color: kLine)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: kSurface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: kLine)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: kLine)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: kLine)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: kInk, width: 1.6)),
      filled: true,
      fillColor: kSurface,
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          backgroundColor: kInk, foregroundColor: kOnInk, shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          foregroundColor: kInk, side: BorderSide(color: kLine), shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kInk)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: kInk, foregroundColor: kOnInk),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurface,
      indicatorColor: kBlush,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kSurface,
      side: BorderSide(color: kLine),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: kSurface, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: kSurface, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class KolakGamilaApp extends StatelessWidget {
  const KolakGamilaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppPrefs.version,
      builder: (context, v, _) => MaterialApp(
        key: ValueKey('theme$v'),
        title: kStoreName,
        debugShowCheckedModeBanner: false,
        locale: Locale('ar'),
        supportedLocales: [Locale('ar'), Locale('en')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(),
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: AppPrefs.textScale,
          builder: (context, scale, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? SizedBox(),
          ),
        ),
        home: AuthGate(),
      ),
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
          return Scaffold(body: Loading());
        }
        final user = snap.data;
        if (user == null) return LoginScreen();
        if (isAdmin) {
          Me.owner = true;
          Me.name = 'صاحب المحل';
          Me.perms = kPerms.keys.toSet();
          return AdminHome(key: ValueKey('owner'));
        }
        // الدخول بالإيميل لصاحب المحل بس
        if (!(user.email ?? '').endsWith('@$kUserDomain')) return _NotAllowed();
        return UserGate(key: ValueKey(user.uid));
      },
    );
  }
}

class _NotAllowed extends StatelessWidget {
  const _NotAllowed();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: EmptyView('الدخول بالإيميل لصاحب المحل بس',
            text: 'العملاء والموظفين بيدخلوا برقم الموبايل.', icon: Icons.lock_outline),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: FilledButton(onPressed: () => auth.signOut(), child: Text('رجوع')),
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
        if (!snap.hasData) return Scaffold(body: Loading());
        final me = snap.data!.data();
        if (me == null) return CompleteProfile();
        if (me['disabled'] == true) {
          return Scaffold(
            body: EmptyView('الحساب ده موقوف',
                text: 'كلّم المحل عشان يفعّله تاني.', icon: Icons.lock_outline),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: OutlinedButton(onPressed: () => auth.signOut(), child: Text('خروج')),
              ),
            ),
          );
        }
        if (me['role'] == 'staff') {
          Me.owner = false;
          Me.name = (me['name'] ?? '').toString();
          Me.perms = ((me['perms'] as List?) ?? []).map((e) => e.toString()).toSet();
          return AdminHome(key: ValueKey('staff'));
        }
        return CustomerHome(me: me);
      },
    );
  }
}
