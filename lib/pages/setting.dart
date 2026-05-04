import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Container(
            color: Theme.of(context).cardColor,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: const Text('Account'),
              subtitle: Text(user?.email ?? 'Not logged in'),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, currentMode, child) {
                    final isDark = currentMode == ThemeMode.dark;
                    return ListTile(
                      leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: Colors.blue),
                      title: const Text('Dark Mode'),
                      subtitle: Text(isDark ? 'On' : 'Off'),
                      trailing: Switch(
                        value: isDark,
                        onChanged: (val) {
                          themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                        },
                        activeColor: Colors.blue,
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.notifications, color: Colors.amber),
                  title: const Text('Notifications'),
                  trailing: Switch(
                    value: true,
                    onChanged: (val) {},
                    activeColor: Colors.blue,
                  ),
                ),
                const Divider(height: 1, indent: 56),
                const ListTile(
                  leading: Icon(Icons.info, color: Colors.grey),
                  title: Text('About'),
                  subtitle: Text('Cash App v1.0.0'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            color: Theme.of(context).cardColor,
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                await Supabase.instance.client.auth.signOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
