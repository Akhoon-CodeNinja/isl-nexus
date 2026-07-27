import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:isl_app/views/auth/verification_screen.dart';
import 'package:isl_app/services/auth_service.dart';
import 'package:isl_app/core/services/api_service.dart'; // Ensure ApiService is imported

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _empIdCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmPassCtrl = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _agreedToTerms = false;
  bool _loading = false;
  
  // Dynamic Departments State
  bool _loadingDepartments = true;
  List<Map<String, dynamic>> _departmentsList = [];
  int? _selectedDepartmentId;
  String? _selectedDepartmentName;

  final AuthService _authService = AuthService();

  final RegExp m365EmailRegex = RegExp(
    r'^[a-zA-Z0-9_.+-]+@(?:[a-zA-Z0-9-]+\.)?(isl\.com\.pk|isl\.onmicrosoft\.com)$',
  );

  final Color islBlue = const Color(0xFF163E75);
  final Color islLightBlue = const Color(0xFFF0F5FA);

  @override
  void initState() {
    super.initState();
    _fetchDepartments();
  }

  Future<void> _fetchDepartments() async {
    try {
      // Fetch dynamic departments from Django API
      final depts = await ApiService().fetchDepartments();
      if (mounted) {
        setState(() {
          _departmentsList = depts;
          _loadingDepartments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingDepartments = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load departments list.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _empIdCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    if (!_agreedToTerms) return;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDepartmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your department.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await _authService.register(
        employeeId: _empIdCtrl.text.trim(),
        password: _passCtrl.text,
        fullName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        department: _selectedDepartmentId!,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VerificationScreen(
            employeeId: _empIdCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            fullName: _nameCtrl.text.trim(),
            department: _selectedDepartmentName ?? 'General',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildDropdownField() {
    if (_loadingDepartments) {
      return Container(
        height: 52,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF163E75)),
            ),
            SizedBox(width: 12),
            Text('Loading departments...', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return DropdownButtonFormField<int>(
      initialValue: _selectedDepartmentId,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.domain, color: Colors.grey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: islBlue, width: 1.5),
        ),
      ),
      hint: const Text("Select your department", style: TextStyle(color: Colors.grey, fontSize: 14)),
      items: _departmentsList.map((dept) {
        return DropdownMenuItem<int>(
          value: dept['id'] is int ? dept['id'] : int.parse(dept['id'].toString()),
          child: Text(dept['name'].toString()),
        );
      }).toList(),
      onChanged: (value) {
        final selectedObj = _departmentsList.firstWhere(
          (d) => d['id'].toString() == value.toString(),
          orElse: () => {'name': ''},
        );
        setState(() {
          _selectedDepartmentId = value;
          _selectedDepartmentName = selectedObj['name'].toString();
        });
      },
      validator: (v) => v == null ? 'Please select a department' : null,
    );
  }

  // ... (Rest of build method, Steppers, TextFields, etc. remain clean as in original)
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Create Account", textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: islBlue)),
                      const SizedBox(height: 8),
                      const Text("Join ISL and get instant access to\nknowledge and support", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 30),

                      _buildInputLabel("Full Name"),
                      _buildTextField(controller: _nameCtrl, hintText: "Enter your full name", prefixIcon: Icons.person_outline, validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your full name' : null),

                      _buildInputLabel("Employee ID"),
                      _buildTextField(controller: _empIdCtrl, hintText: "Enter your employee ID", prefixIcon: Icons.badge_outlined, validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your employee ID' : null),

                      _buildInputLabel("Department"),
                      _buildDropdownField(),

                      _buildInputLabel("Email Address"),
                      _buildTextField(
                        controller: _emailCtrl,
                        hintText: "e.g., name@isl.onmicrosoft.com",
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter your email';
                          if (!m365EmailRegex.hasMatch(v.trim())) return 'Use your ISL email address';
                          return null;
                        },
                      ),

                      _buildInputLabel("Password"),
                      _buildTextField(
                        controller: _passCtrl,
                        hintText: "Create a password",
                        prefixIcon: Icons.lock_outline,
                        isPassword: true,
                        isVisible: _isPasswordVisible,
                        onVisibilityToggle: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please create a password';
                          if (v.length < 8) return 'Minimum 8 characters';
                          return null;
                        },
                      ),

                      _buildInputLabel("Confirm Password"),
                      _buildTextField(
                        controller: _confirmPassCtrl,
                        hintText: "Confirm your password",
                        prefixIcon: Icons.lock_outline,
                        isPassword: true,
                        isVisible: _isConfirmPasswordVisible,
                        onVisibilityToggle: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                        validator: (v) {
                          if (v != _passCtrl.text) return 'Passwords do not match';
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _agreedToTerms,
                              activeColor: islBlue,
                              onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(child: Text("I agree to the Terms of Service and Privacy Policy", style: TextStyle(fontSize: 12))),
                        ],
                      ),
                      const SizedBox(height: 24),

                      ElevatedButton(
                        onPressed: (_agreedToTerms && !_loading) ? _handleContinue : null,
                        style: ElevatedButton.styleFrom(backgroundColor: islBlue, padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: _loading 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text("Continue", style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) => Padding(padding: const EdgeInsets.only(bottom: 8.0, top: 14.0), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)));
  
  Widget _buildTextField({required TextEditingController controller, required String hintText, required IconData prefixIcon, bool isPassword = false, bool isVisible = false, VoidCallback? onVisibilityToggle, TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !isVisible,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(prefixIcon, color: Colors.grey),
        suffixIcon: isPassword ? IconButton(icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off), onPressed: onVisibilityToggle) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}