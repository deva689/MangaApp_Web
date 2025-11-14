import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:manga/auth/phone_input.dart';
import 'package:manga/main_nav.dart'; // ✅ import home screen

const supabaseUrl = 'https://glofplyipqsoirrawnxf.supabase.co';
const supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdsb2ZwbHlpcHFzb2lycmF3bnhmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIzMDM0MzAsImV4cCI6MjA3Nzg3OTQzMH0.E9KcDsTptE-W2cwwcACI_qctxcHupRytklx8QWwIzw8';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);

  runApp(const ProviderScope(child: MainApp())); // ✅ Wrapped with ProviderScope
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return MaterialApp(
      debugShowCheckedModeBanner: false,

      /// ✅ Auto-login Check
      home: supabase.auth.currentUser != null
          ? const MainNav() // 👉 User already logged in → go to HomeScreen
          : const PhoneInputScreen(), // 👉 Not logged in → go to Login Screen
    );
  }
}
