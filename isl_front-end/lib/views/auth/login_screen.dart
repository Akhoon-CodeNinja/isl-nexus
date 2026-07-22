import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:aad_oauth/aad_oauth.dart';
import 'package:aad_oauth/model/config.dart' as aad;
import 'package:isl_app/core/constants/app_colors.dart';
import 'package:isl_app/core/models/auth_models.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/views/admin/admin_dashboard_screen.dart';
import 'package:isl_app/views/worker/worker_chat_screen.dart';
import 'package:isl_app/widgets/auth/auth_text_field.dart';
import 'package:isl_app/widgets/auth/auth_buttons.dart';
import 'package:isl_app/core/utils/globals.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isWorker = true;
  bool _hidePass = true;
  bool _loading = false;

  // --- MICROSOFT OAUTH CONFIGURATION ---
static final aad.Config oauthConfig = aad.Config(
  tenant: 'common',
  clientId: 'YOUR_AZURE_CLIENT_ID',
  scope: 'openid profile email User.Read',
  redirectUri: 'https://login.live.com/oauth20_desktop.srf',
  navigatorKey: appNavigatorKey,
);

  // Built lazily rather than as an eager field initializer. AadOAuth's
  // web implementation touches the browser's MSAL JS SDK (window.msal)
  // the moment it's constructed — and since web/index.html doesn't load
  // that script, constructing it eagerly here crashed the ENTIRE app on
  // startup ("Cannot read properties of undefined (reading 'init')"),
  // before the login form even had a chance to render. Deferring
  // construction to first actual use (tapping "Continue with Microsoft
  // 365") means the rest of the app works regardless, and only that one
  // feature fails — inside its own try/catch — if MSAL isn't set up yet.
  AadOAuth? _oauth;
  AadOAuth get oauth => _oauth ??= AadOAuth(oauthConfig);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final appState = context.read<AppState>();
    await appState.signIn(
      identifier: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );

    if (!mounted) return;

    if (appState.error != null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appState.error!),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    final role = (appState.session?.role ?? '').toUpperCase();
    final isActualAdmin = role == 'DEPARTMENT_HEAD';

    // Check: UI selection vs Actual Role
    final bool selectedAdmin = !_isWorker;

    if (selectedAdmin != isActualAdmin) {
      await appState.logout();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Invalid credentials. Please select the correct role.'),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    setState(() => _loading = false);

    final destination = isActualAdmin
        ? const AdminDashboardScreen()
        : const WorkerChatScreen();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Signed in as ${appState.session?.fullName ?? 'user'}.'),
      ),
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  Future<String?> _getMicrosoftAccessToken() async {
    try {
      // Login ka popup/screen open karega
      await oauth.login();
      
      // Successful login k baad token get karega
      final String? accessToken = await oauth.getAccessToken();
      
      if (accessToken != null) {
        return accessToken;
      } else {
        throw Exception('Token received was null. User might have cancelled.');
      }
    } catch (e) {
      throw Exception('Microsoft Login Failed: $e');
    }
  }

  Future<void> _handleMicrosoftSignIn() async {
    setState(() => _loading = true);
    try {
      final msAccessToken = await _getMicrosoftAccessToken();
      if (msAccessToken == null) {
        setState(() => _loading = false);
        return;
      }

      // Direct API Call without AppState error
      final apiService = ApiService();
      final responseData = await apiService.loginWithMicrosoftToken(msAccessToken);

      if (!mounted) return;

      final session = AuthSession.fromJson(responseData);
      await apiService.saveSession(session);

      final role = session.role.toUpperCase();
      final destination = role == 'DEPARTMENT_HEAD'
          ? const AdminDashboardScreen()
          : const WorkerChatScreen();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => destination),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyApiError(e)),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeroSection(),
                  _FormCard(
                    formKey: _formKey,
                    emailCtrl: _emailCtrl,
                    passCtrl: _passCtrl,
                    isWorker: _isWorker,
                    hidePass: _hidePass,
                    loading: _loading,
                    onRoleToggle: (v) => setState(() => _isWorker = v),
                    onPassToggle: () => setState(() => _hidePass = !_hidePass),
                    onSignIn: _signIn,
                    onMicrosoftSignIn: _handleMicrosoftSignIn,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 210,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('lib/pictures/Screenshot 2026-07-11 104511.png'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.30),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.settings, size: 46, color: AppColors.primary),
                      Icon(
                        Icons.factory_outlined,
                        size: 21,
                        color: AppColors.primary.withValues(alpha: 0.9),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'ISL',
                  style: GoogleFonts.inter(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 3,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.40),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Industrial Solutions Ltd.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.90),
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.isWorker,
    required this.hidePass,
    required this.loading,
    required this.onRoleToggle,
    required this.onPassToggle,
    required this.onSignIn,
    required this.onMicrosoftSignIn,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool isWorker;
  final bool hidePass;
  final bool loading;
  final ValueChanged<bool> onRoleToggle;
  final VoidCallback onPassToggle;
  final VoidCallback onSignIn;
  final VoidCallback onMicrosoftSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x221B3F7A),
            blurRadius: 30,
            spreadRadius: 2,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome Back!',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sign in to your account to continue',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textLight,
              ),
            ),
            const SizedBox(height: 22),
            _RoleToggle(isWorker: isWorker, onChanged: onRoleToggle),
            const SizedBox(height: 30),
            AuthTextField(
              controller: emailCtrl,
              label: 'Email or Employee ID',
              hintText: 'Enter your email or employee ID',
              prefixIcon: Icons.person_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter your email or employee ID'
                  : null,
            ),
            const SizedBox(height: 16),
            AuthTextField(
              controller: passCtrl,
              label: 'Password',
              hintText: 'Enter your password',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: hidePass,
              textInputAction: TextInputAction.done,
              suffixWidget: IconButton(
                icon: Icon(
                  hidePass
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textLight,
                  size: 20,
                ),
                onPressed: onPassToggle,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter your password';
                if (v.length < 6) return 'Minimum 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Forgot Password'),
                      content: const Text(
                        'Password recovery is not available yet. Please contact your Department Head for account assistance.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot Password?',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Sign In',
              icon: Icons.arrow_forward_rounded,
              onPressed: onSignIn,
              isLoading: loading,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Container(height: 1, color: AppColors.divider)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'or continue with',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textLight,
                    ),
                  ),
                ),
                Expanded(child: Container(height: 1, color: AppColors.divider)),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedActionButton(
              label: 'Continue with Microsoft 365',
              leadingWidget: SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(painter: _MPainter()),
              ),
              onPressed: loading ? null : onMicrosoftSignIn,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleToggle extends StatelessWidget {
  const _RoleToggle({required this.isWorker, required this.onChanged});
  final bool isWorker;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentTab(
              label: 'Users',
              icon: Icons.person_outline,
              active: isWorker,
              onTap: () => onChanged(true),
            ),
          ),
          Container(width: 1, color: Colors.grey.shade300),
          Expanded(
            child: _SegmentTab(
              label: 'Department Head',
              icon: Icons.shield_outlined,
              active: !isWorker,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        color: active ? AppColors.primary : Colors.white,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width * 0.09;
    final half = (size.width - gap) / 2;
    final data = [
      (0.0, 0.0, const Color(0xFFF25022)),
      (half + gap, 0.0, const Color(0xFF7FBA00)),
      (0.0, half + gap, const Color(0xFF00A4EF)),
      (half + gap, half + gap, const Color(0xFFFFB900)),
    ];
    for (final d in data) {
      canvas.drawRect(
        Rect.fromLTWH(d.$1, d.$2, half, half),
        Paint()..color = d.$3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}