import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sizer/sizer.dart'; 
import 'firebase_options.dart';

// استيراد الشاشات
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/rep/sales_rep_home_screen.dart';
import 'screens/rep/visit_screen.dart';
import 'screens/rep/add_new_customer.dart';
import 'screens/admin/sales_management_dashboard.dart';
import 'screens/admin/live_monitoring_screen.dart';
import 'screens/admin/manage_users_screen.dart'; // 🛑 استيراد شاشة الإدارة الجديدة

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
    return Sizer(
      builder: (context, orientation, deviceType) {
        return MaterialApp(
          title: 'Aksab Sales App',
          debugShowCheckedModeBanner: false,

          // إعداد اتجاه اللغة للعربية بشكل افتراضي
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            );
          },
          theme: ThemeData(
            primarySwatch: Colors.green,
            fontFamily: 'Cairo',
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF43B97F),
              primary: const Color(0xFF43B97F),
            ),
          ),

          // تعريف مسارات التنقل (Named Routes)
          initialRoute: '/',
          routes: {
            '/': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/rep_home': (context) => const SalesRepHomeScreen(),
            '/visits': (context) => const VisitScreen(),
            '/add_customer': (context) => const AddNewCustomerScreen(),

            // --- مسارات الإدارة (Admin Routes) ---
            '/admin_dashboard': (context) => const SalesManagementDashboard(),
            '/live_monitoring': (context) => const LiveMonitoringScreen(),
            '/manage_users': (context) => const ManageUsersScreen(), // 🛑 المسار الجديد للمندوبين والمشرفين
          },
        );
      },
    );
  }
}

