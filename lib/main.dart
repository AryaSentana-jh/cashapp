import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/wallet.dart';
import 'pages/home.dart';
import 'pages/signup.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<String> currencyNotifier = ValueNotifier('₱');
final ValueNotifier<List<Wallet>> walletsNotifier = ValueNotifier([]);

final Map<String, double> exchangeRates = {
  '₱': 1.0,
  '\$': 0.018,    // 1 PHP = ~0.018 USD
  '€': 0.016,    // 1 PHP = ~0.016 EUR
  '£': 0.014,    // 1 PHP = ~0.014 GBP
  '¥': 2.68,     // 1 PHP = ~2.68 JPY
  'Rp': 282.5,   // 1 PHP = ~282.5 IDR
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://cwalcojbapnrycldgvot.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN3YWxjb2piYXBucnljbGRndm90Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxOTM1NjEsImV4cCI6MjA5MTc2OTU2MX0.82_xotMyfqCGnP6IIR-6YHySEpjm0bSNAz1P2OuR0rA',
  );

  final prefs = await SharedPreferences.getInstance();
  
  // Load Saved Currency
  final savedCurrency = prefs.getString('selected_currency') ?? '₱';
  currencyNotifier.value = savedCurrency;

  // Load Saved Theme
  final savedTheme = prefs.getString('theme_mode') ?? 'light';
  themeNotifier.value = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;

  // Load Saved Wallets
  final savedWallets = prefs.getString('wallets');
  if (savedWallets != null && savedWallets.isNotEmpty) {
    try {
      final list = (jsonDecode(savedWallets) as List)
          .map((e) => Wallet.fromJson(e as Map<String, dynamic>))
          .toList();
      walletsNotifier.value = list;
    } catch (_) {}
  }
  if (walletsNotifier.value.isEmpty) {
    walletsNotifier.value = [
      const Wallet(id: 'default_cash',   name: 'Cash',   iconName: 'cash',        colorValue: 0xFFFF8C00),
      const Wallet(id: 'default_card',   name: 'Card',   iconName: 'credit_card', colorValue: 0xFF7C3AED),
    ];
  }

  // Persist Changes Automatically
  currencyNotifier.addListener(() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('selected_currency', currencyNotifier.value);
  });

  themeNotifier.addListener(() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('theme_mode', themeNotifier.value == ThemeMode.dark ? 'dark' : 'light');
  });

  walletsNotifier.addListener(() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'wallets',
      jsonEncode(walletsNotifier.value.map((w) => w.toJson()).toList()),
    );
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Cash App',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          darkTheme: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: currentMode,
          home: Supabase.instance.client.auth.currentSession != null
              ? const HomePage()
              : const LoginPage(),
        );
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() == true) {
      setState(() => _isLoading = true);
      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                'Welcome back',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to continue to your account.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(value.trim())) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Log In'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('New here?'),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SignupPage(),
                        ),
                      );
                    },
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
