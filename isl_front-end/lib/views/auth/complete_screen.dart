import 'package:flutter/material.dart';
import 'package:isl_app/views/auth/login_screen.dart'; // Ensure correct path

class CompleteScreen extends StatelessWidget {
  const CompleteScreen({
    super.key,
    required this.fullName,
    required this.employeeId,
    required this.department,
    required this.email,
  });

  final String fullName;
  final String employeeId;
  final String department;
  final String email;

  final Color islBlue = const Color(0xFF163E75);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFB8D0ED),
        elevation: 0,
        automaticallyImplyLeading: false, // Success screen par back button nahi hona chahiye
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

                    // --- Custom Stepper (Step 3 Active) ---
                    _buildStepper(),
                    const SizedBox(height: 30),

                    // --- Success Animation/Icon ---
                    Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.green.shade500,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            )
                          ],
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 60),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Title & Subtitle ---
                    Text(
                      "Account Created Successfully!",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: islBlue),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Welcome to ISL! Your account is ready to use.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),

                    // --- Account Summary Card ---
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.account_circle, color: islBlue),
                                const SizedBox(width: 10),
                                Text(
                                  "Your Account Summary",
                                  style: TextStyle(fontWeight: FontWeight.bold, color: islBlue, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                _buildSummaryRow(Icons.person_outline, "Full Name", fullName),
                                const Divider(height: 24),
                                _buildSummaryRow(Icons.badge_outlined, "Employee ID", employeeId),
                                const Divider(height: 24),
                                _buildSummaryRow(Icons.domain, "Department", department),
                                const Divider(height: 24),
                                _buildSummaryRow(Icons.email_outlined, "Email", email),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    // --- Go to Login Button (Replaced Dashboard/Chat buttons) ---
                    ElevatedButton(
                      onPressed: () {
                        // PushAndRemoveUntil clears the back-stack so user can't press back to go to success screen
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: islBlue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text("Go to Login", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Footer Banner ---
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user, color: Colors.green.shade700, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Your account is secure and all set!",
                                  style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "You can now securely log in to access ISL systems.",
                                  style: TextStyle(color: Colors.green.shade800, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- Copyright Footer ---
                    const Center(
                      child: Text(
                        "© 2026 Industrial Solutions Ltd. All rights reserved.",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    )
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

  Widget _buildSummaryRow(IconData icon, String label, String value, {bool isBadge = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        const Spacer(),
        if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F0FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(color: islBlue, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          )
        else
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
          ),
      ],
    );
  }

  Widget _buildStepper() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStepItemCompleted("Account Info"),
        _buildStepDivider(isActive: true),
        _buildStepItemCompleted("Verification"),
        _buildStepDivider(isActive: true),
        _buildStepItemActive("3", "Complete"),
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