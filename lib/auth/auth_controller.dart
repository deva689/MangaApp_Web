import 'package:flutter_riverpod/legacy.dart';
import 'package:manga/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth State
class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final String? phone;

  AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.phone,
  });

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? phone,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      phone: phone ?? this.phone,
    );
  }
}

/// Auth Controller using Riverpod StateNotifier
class AuthController extends StateNotifier<AuthState> {
  final SupabaseClient _client;

  AuthController(this._client) : super(AuthState());

  /// Send OTP
  Future<void> sendOtp(String phone) async {
    if (phone.isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter your phone number');
      return;
    }

    final formattedPhone = phone.startsWith('+') ? phone : '+91$phone';
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await _client.auth.signInWithOtp(phone: formattedPhone);
      state = state.copyWith(isLoading: false, phone: formattedPhone);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Verify OTP
  Future<AuthResponse?> verifyOtp(String otp) async {
    if (otp.isEmpty || otp.length < 4) {
      state = state.copyWith(errorMessage: 'Please enter a valid OTP');
      return null;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _client.auth.verifyOTP(
        phone: state.phone!,
        token: otp,
        type: OtpType.sms,
      );
      state = state.copyWith(isLoading: false);
      return response;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }
}

/// Provider
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthController(client);
});
