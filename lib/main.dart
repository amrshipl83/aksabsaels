import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// استيراد الشاشات
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart'; // أضف هذا السطر
import 'screens/rep/sales_rep_home_screen.dart';
import 'screens/rep/visit_screen.dart'; // أضف هذا السطر

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const AksabSalesApp());
}

class AksabSalesApp extends StatelessWidget {
  const AksabSalesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aksab Sales App',
      debugShowCheckedModeBanner: false,

      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },

      theme: ThemeData(
        primarySwatch: Colors.orange,
        fontFamily: 'Cairo', // تأكد من إضافة الخط في pubspec.yaml
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF43B97F)), // جعلنا اللون الأساسي أخضر ليتماشى مع الهوية
      ),

      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(), // مسار التسجيل
        '/rep_home': (context) => const SalesRepHomeScreen(), // مسار المندوب
        '/visits': (context) => const VisitScreen(), // مسار الزيارات
      },
    );
  }
}

