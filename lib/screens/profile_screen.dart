import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manga/auth/phone_input.dart';
import 'package:manga/screens/downloads_page.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // Logout
  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("phone");

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PhoneInputScreen()),
      (route) => false,
    );
  }

  Future<String?> _getPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("phone");
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 26, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    String? trailingText,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.black),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff8f8f8),
      appBar: AppBar(
        title: const Text(
          "Profile",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),

      body: FutureBuilder<String?>(
        future: _getPhone(),
        builder: (context, snapshot) {
          return SingleChildScrollView(
            child: Column(
              children: [
                // PROFILE CARD
                SizedBox(height: 12),

                Text(
                  "Account",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12),

                _menuTile(
                  icon: Icons.person_outline,
                  title: "Manage Profile",
                  onTap: () {},
                ),
                const SizedBox(height: 10),

                _menuTile(
                  icon: Icons.lock_outline,
                  title: "Password & Security",
                  onTap: () {},
                ),
                const SizedBox(height: 10),

                _menuTile(
                  icon: Icons.notifications_none,
                  title: "Notifications",
                  onTap: () {},
                ),
                const SizedBox(height: 10),

                _menuTile(
                  icon: Icons.language,
                  title: "Language",
                  trailingText: "English",
                ),

                SizedBox(height: 12),

                Text(
                  "Preferences",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12),

                // ---------- PREFERENCES ----------
                _menuTile(icon: Icons.info_outline, title: "About Us"),
                const SizedBox(height: 10),

                _menuTile(
                  icon: Icons.color_lens_outlined,
                  title: "Theme",
                  trailingText: "Light",
                ),
                const SizedBox(height: 10),

                _menuTile(
                  icon: Icons.download_outlined,
                  title: "Downloads",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DownloadsPage()),
                    );
                  },
                ),

                // ---------- SUPPORT ----------
                SizedBox(height: 12),

                Text(
                  "Support",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12),

                _menuTile(
                  icon: Icons.headset_mic_outlined,
                  title: "Help & Support",
                ),
                const SizedBox(height: 10),

                // LOGOUT BUTTON
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _logout(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "Logout",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}
