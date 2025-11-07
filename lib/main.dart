import 'package:flutter/material.dart';
import 'package:manga/screens/homescreen.dart';
import 'package:manga/main_nav.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://glofplyipqsoirrawnxf.supabase.co';
const supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdsb2ZwbHlpcHFzb2lycmF3bnhmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIzMDM0MzAsImV4cCI6MjA3Nzg3OTQzMH0.E9KcDsTptE-W2cwwcACI_qctxcHupRytklx8QWwIzw8'; // <-- paste the anon key directly here

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // <-- required

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const MainNav(),
    );
  }
}
