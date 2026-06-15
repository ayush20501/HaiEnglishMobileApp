import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:haienglish/services/api_service.dart';
import 'package:haienglish/models/user.dart';
import 'package:haienglish/models/course.dart';
import 'package:haienglish/screens/auth_screen.dart';
import 'package:haienglish/screens/dashboard_screen.dart';
import 'package:haienglish/screens/checkout_screen.dart';
import 'package:haienglish/screens/certificate_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF9FAFB),
      statusBarIconBrightness: Brightness.dark,
    ));

    return MaterialApp(
      title: 'HaiEnglish',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF004AAD),
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF004AAD),
          primary: const Color(0xFF004AAD),
          secondary: const Color(0xFF10B981),
        ),
      ),
      home: const MainNavigator(),
    );
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  User? _currentUser;
  String _currentScreen = 'auth';
  Course? _selectedCourse;

  void _onLoginSuccess(User user) {
    setState(() {
      _currentUser = user;
      _currentScreen = 'dashboard';
    });
  }



  void _onEnrollCourse(Course course) {
    setState(() {
      _selectedCourse = course;
      _currentScreen = 'checkout';
    });
  }

  void _onPaymentSuccess() {
    setState(() {
      _currentScreen = 'dashboard';
    });
  }

  void _onViewCertificate(Course course) {
    setState(() {
      _selectedCourse = course;
      _currentScreen = 'certificate';
    });
  }

  void _onLogOut() {
    setState(() {
      _currentUser = null;
      _selectedCourse = null;
      _currentScreen = 'auth';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null || _currentScreen == 'auth') {
      return AuthScreen(onLoginSuccess: _onLoginSuccess);
    }

    switch (_currentScreen) {
      case 'dashboard':
        return DashboardScreen(
          user: _currentUser!,
          onEnrollCourse: _onEnrollCourse,
          onViewCertificate: _onViewCertificate,
          onLogOut: _onLogOut,
        );
      case 'checkout':
        return CheckoutScreen(
          course: _selectedCourse!,
          user: _currentUser!,
          onBack: () => setState(() => _currentScreen = 'dashboard'),
          onPaymentSuccess: _onPaymentSuccess,
        );
      case 'certificate':
        return CertificateScreen(
          course: _selectedCourse!,
          user: _currentUser!,
          onBack: () => setState(() => _currentScreen = 'dashboard'),
        );
      default:
        return Scaffold(
          body: Center(
            child: Text('Screen $_currentScreen not found'),
          ),
        );
    }
  }
}
