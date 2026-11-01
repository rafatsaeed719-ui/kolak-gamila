import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// بيانات مشروع Firebase (kolak-gamila)
const FirebaseOptions _android = FirebaseOptions(
  apiKey: 'AIzaSyBNL4y_St-ju7COwN66fWR7UV7_t3qhIEY',
  appId: '1:749907246980:android:26c3dc3023ce20b88be7d1',
  messagingSenderId: '749907246980',
  projectId: 'kolak-gamila',
  storageBucket: 'kolak-gamila.firebasestorage.app',
);

// نسخة الكمبيوتر (الويب)
const FirebaseOptions _web = FirebaseOptions(
  apiKey: 'AIzaSyCFX0XkEVLjPLqv8GiYf3-K4_hfq7PmyXA',
  appId: '1:749907246980:web:e3bd3fedc527436a8be7d1',
  messagingSenderId: '749907246980',
  projectId: 'kolak-gamila',
  authDomain: 'kolak-gamila.firebaseapp.com',
  storageBucket: 'kolak-gamila.firebasestorage.app',
  measurementId: 'G-2M5G0B7PWR',
);

FirebaseOptions get kgFirebaseOptions => kIsWeb ? _web : _android;
