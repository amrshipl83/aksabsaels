import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// استيراد الشاشات
import 'screens/auth/login_screen.dart';
import 'screens/rep/sales_rep_home_screen.dart'; // الشاشة التي صممناها للتو

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
      debugShowCheckedModeBanner: false, // إخفاء علامة Debug
      
      // إعدادات اللغة والاتجاه
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },

      theme: ThemeData(
        primarySwatch: Colors.orange,
        fontFamily: 'Cairo', 
        useMaterial3: true,
        // تخصيص اللون البرتقالي كثيم أساسي
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF57C00)),
      ),

      // تعريف المسارات (Routes) لتسهيل التنقل
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/rep_home': (context) => const SalesRepHomeScreen(),
        // سنضيف هنا شاشات المدير والزيارات لاحقاً
      },
    );
  }
}
