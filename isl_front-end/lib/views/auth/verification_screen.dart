import 'dart:async';
import 'package:flutter/material.dart';
import 'package:isl_app/services/auth_service.dart';
import 'package:isl_app/views/auth/complete_screen.dart';

/// Auth screen — OTP/verification step during sign-up.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    required this.employeeId,
    required this.email,
    required this.fullName,
    required this.department,
  });

  final String employeeId;
  final String email;
  final String fullName;
  final String department;

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final Color islBlue = const Color(0xFF163E75);
  final AuthService _authService = AuthService();

  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _verifying = false;
  bool _resending = false;

  Timer? _resendTimer;
  int _secondsRemaining = 60;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _secondsRemaining = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsRemaining = 0);
      } else {
        if (mounted) setState(() => _secondsRemaining--);
      }
    });
  }

  String get _otpValue => _otpCtrls.map((c) => c.text).join();

  Future<void> _handleVerify() async {
    final otp = _otpValue;
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the full 6-digit code.')),
      );
      return;
    }

    setState(() => _verifying = true);

    try {
      await _authService.verifyOtp(employeeId: widget.employeeId, otp: otp);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CompleteScreen(
            fullName: widget.fullName,
            employeeId: widget.employeeId,
            department: widget.department,
            email: widget.email,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
      for (final c in _otpCtrls) {
        c.clear();
      }
      _otpFocusNodes.first.requestFocus();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _handleResend() async {
    if (_secondsRemaining > 0 || _resending) return;

    setState(() => _resending = true);

    try {
      final message = await _authService.resendOtp(employeeId: widget.employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      _startResendTimer();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _onDigitChanged(String value, int index) {
    if (value.isNotEmpty && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
    if (index == 5 && value.isNotEmpty && _otpValue.length == 6) {
      FocusScope.of(context).unfocus();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFB8D0ED),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB8D0ED), Color(0xFFCFDFEF), Color(0xFFDAE8F7)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x221B3F7A),
                    blurRadius: 30,
                    spreadRadius: 2,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- ISL Logo Header ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings, color: islBlue, size: 36),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "ISL",
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: islBlue, letterSpacing: 1.5),
                            ),
                            const Text(
                              "Industrial Solutions Ltd.",
                              style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 30),

                    // --- Custom Stepper (Step 2 Active) ---
                    _buildStepper(),
                    const SizedBox(height: 30),

                    // --- Title & Subtitle ---
                    Text(
                      "Verify Your Identity",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: islBlue),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "We've sent a 6-digit verification code to",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.email_outlined, size: 18, color: Colors.black87),
                        const SizedBox(width: 6),
                        Text(
                          widget.email,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // --- 6-Digit OTP Input ---
                    const Text(
                      "Enter the 6-digit code",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) => _buildOTPBox(index)),
                    ),
                    const SizedBox(height: 24),

                    // --- Info Boxes ---
                    _buildInfoBox(
                      icon: Icons.shield_outlined,
                      title: "Didn't receive the code?",
                      subtitle: "You can request a new code after the timer ends.",
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _secondsRemaining == 0 ? _handleResend : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_resending)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: islBlue),
                              )
                            else
                              Icon(Icons.access_time, color: islBlue, size: 18),
                            const SizedBox(width: 8),
                            _secondsRemaining > 0
                                ? Row(
                                    children: [
                                      const Text("Resend code in ", style: TextStyle(color: Colors.black87, fontSize: 13)),
                                      Text(
                                        "00:${_secondsRemaining.toString().padLeft(2, '0')}",
                                        style: TextStyle(color: islBlue, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ],
                                  )
                                : Text(
                                    "Resend code",
                                    style: TextStyle(color: islBlue, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Verify Button ---
                    ElevatedButton(
                      onPressed: _verifying ? null : _handleVerify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: islBlue,
                        disabledBackgroundColor: islBlue.withOpacity(0.6),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _verifying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("Verify & Continue", style: TextStyle(fontSize: 16, color: Colors.white)),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                              ],
                            ),
                    ),
                    const SizedBox(height: 30),

                    // --- Secure Information Badge ---
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, color: Colors.green.shade700, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Your information is secure and encrypted",
                                  style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "ISL never shares your data with third parties.",
                                  style: TextStyle(color: Colors.green.shade800, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Methods ---

  Widget _buildOTPBox(int index) {
    final isFilled = _otpCtrls[index].text.isNotEmpty;
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: _otpCtrls[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: TextStyle(color: islBlue, fontSize: 22, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: isFilled ? islBlue : Colors.grey.shade300,
              width: isFilled ? 2.0 : 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: islBlue, width: 2.0),
          ),
        ),
        onChanged: (value) => _onDigitChanged(value, index),
      ),
    );
  }

  Widget _buildInfoBox({required IconData icon, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: islBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: islBlue, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.black87, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStepItemCompleted("Account Info"),
        _buildStepDivider(isActive: true),
        _buildStepItemActive("2", "Verification"),
        _buildStepDivider(isActive: false),
        _buildStepItemInactive("3", "Complete"),
      ],
    );
  }

  Widget _buildStepItemCompleted(String label) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: islBlue, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildStepItemActive(String number, String label) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: islBlue, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: islBlue, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildStepItemInactive(String number, String label) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(number, style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildStepDivider({required bool isActive}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        height: 1.5,
        color: isActive ? islBlue : Colors.grey.shade300,
      ),
    );
  }
}