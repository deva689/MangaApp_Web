import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manga/auth/auth_controller.dart';
import 'package:manga/auth/topic_selection_screen.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String phone;

  const OtpVerificationScreen({super.key, required this.phone});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final List<TextEditingController> controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  int seconds = 60;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      if (seconds == 0) return false;
      setState(() => seconds--);
      return true;
    });
  }

  String getOtp() {
    return controllers.map((c) => c.text).join();
  }

  Future<void> verifyOtp() async {
    final otp = getOtp();

    if (otp.length != 6) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter 6-digit OTP")));
      return;
    }

    final response = await ref
        .read(authControllerProvider.notifier)
        .verifyOtp(otp);

    if (!mounted) return;

    if (response?.user != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("OTP Verified ✅"),
          backgroundColor: Colors.green.shade600,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TopicSelectionScreen()),
        (route) => false,
      );
    }
  }

  Widget otpBox(int index) {
    return Container(
      width: 48,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controllers[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20, color: Colors.black),
        maxLength: 1,
        decoration: const InputDecoration(
          counterText: "",
          border: InputBorder.none,
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            FocusScope.of(context).nextFocus();
          } else if (value.isEmpty && index > 0) {
            FocusScope.of(context).previousFocus();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified, color: Colors.black, size: 60),

              const SizedBox(height: 26),

              const Text(
                "OTP Verification",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                "Enter the OTP sent to ${widget.phone}",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black.withOpacity(0.6)),
              ),

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, otpBox),
              ),

              const SizedBox(height: 24),

              Text(
                seconds > 0
                    ? "Resend OTP in $seconds sec"
                    : "Didn't receive OTP?",
                style: TextStyle(color: Colors.black.withOpacity(0.6)),
              ),

              if (seconds == 0)
                TextButton(
                  onPressed: () {
                    setState(() {
                      seconds = 60;
                      _startTimer();
                    });
                  },
                  child: Text(
                    "Resend Code",
                    style: TextStyle(
                      color: const Color(0xFFEA7A61),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: authState.isLoading ? null : verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA7A61),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Verify OTP",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 18),

              TextButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
                child: Text(
                  "Change Phone Number",
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.7),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}