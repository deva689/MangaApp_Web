import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manga/auth/auth_controller.dart';
import 'package:manga/auth/otp_screen.dart';

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen>
    with SingleTickerProviderStateMixin {
  final controller = TextEditingController();
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  String selectedCountryCode = "+91";

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> sendOtp() async {
    String phone = controller.text.trim();

    if (selectedCountryCode == "+91" && phone.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter valid 10-digit Indian number")),
      );
      return;
    }

    if (selectedCountryCode == "+1" &&
        (phone.length < 10 || phone.length > 11)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter valid US phone number")),
      );
      return;
    }

    await ref
        .read(authControllerProvider.notifier)
        .sendOtp("$selectedCountryCode${controller.text.trim()}");

    final error = ref.read(authControllerProvider).errorMessage;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? "OTP Sent Successfully!"),
        backgroundColor: error != null
            ? Colors.redAccent
            : const Color(0xFFEA7A61),
      ),
    );

    if (error == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(phone: controller.text.trim()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            /// Light brand circle background
            Positioned(
              top: -150,
              right: -80,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  color: const Color(0xFFEA7A61).withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -140,
              left: -90,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  color: const Color(0xFFEA7A61).withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
              ),
            ),

            FadeTransition(
              opacity: _fadeAnim,
              child: SafeArea(
                child: SingleChildScrollView(
                  // ✅ Fixes overflow, supports small screens
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    height: size.height - MediaQuery.of(context).padding.top,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                padding: const EdgeInsets.all(26),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.45),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.black.withOpacity(0.08),
                                  ),
                                ),

                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Icon Circle
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFEA7A61,
                                        ).withOpacity(0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 42,
                                        color: Colors.black,
                                      ),
                                    ),

                                    const SizedBox(height: 22),

                                    const Text(
                                      "Verify Your Phone",
                                      style: TextStyle(
                                        fontSize: 29,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black,
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    Text(
                                      "Enter your mobile number and receive OTP",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black.withOpacity(0.6),
                                      ),
                                    ),

                                    const SizedBox(height: 26),

                                    // ✅ Country Code + TextField
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: selectedCountryCode,
                                              icon: const Icon(
                                                Icons.keyboard_arrow_down,
                                              ),
                                              items: const [
                                                DropdownMenuItem(
                                                  value: "+91",
                                                  child: Text("🇮🇳 +91"),
                                                ),
                                                DropdownMenuItem(
                                                  value: "+1",
                                                  child: Text("🇺🇸 +1"),
                                                ),
                                              ],
                                              onChanged: (value) {
                                                setState(() {
                                                  selectedCountryCode = value!;
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),

                                        Expanded(
                                          child: TextField(
                                            controller: controller,
                                            keyboardType: TextInputType.phone,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 16,
                                            ),
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: Colors.grey.shade200,
                                              hintText: "Enter phone number",
                                              hintStyle: TextStyle(
                                                color: Colors.black.withOpacity(
                                                  0.5,
                                                ),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                borderSide: BorderSide.none,
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 18,
                                                    vertical: 20,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 22),

                                    SizedBox(
                                      width: double.infinity,
                                      height: 54,
                                      child: ElevatedButton(
                                        onPressed: authState.isLoading
                                            ? null
                                            : sendOtp,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFEA7A61,
                                          ),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        child: authState.isLoading
                                            ? const SizedBox(
                                                height: 22,
                                                width: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Text(
                                                "Send OTP",
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    Center(
                                      child: TextButton(
                                        onPressed: () {
                                          if (Navigator.canPop(context)) {
                                            Navigator.pop(context);
                                          }
                                        },
                                        child: Text(
                                          "Continue as Guest",
                                          style: TextStyle(
                                            color: Colors.black.withOpacity(
                                              0.7,
                                            ),
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
