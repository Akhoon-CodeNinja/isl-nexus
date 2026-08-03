import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:google_fonts/google_fonts.dart';
import 'package:isl_app/core/constants/app_colors.dart';
import 'package:isl_app/core/providers/app_state.dart';
import 'package:isl_app/services/auth_service.dart';
import 'package:isl_app/views/Head/department_head_dashboard_screen.dart';
import 'package:isl_app/views/Admin/admin_dashboard_screen.dart';
import 'package:isl_app/views/auth/login_screen.dart';
import 'package:isl_app/views/worker/worker_chat_screen.dart';
import 'package:provider/provider.dart';
import 'package:isl_app/core/utils/globals.dart';



void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock orientation to portrait for mobile
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ISLApp());
}

class ISLApp extends StatefulWidget {
  const ISLApp({super.key});

  @override
  State<ISLApp> createState() => _ISLAppState();
}

class _ISLAppState extends State<ISLApp> {
  final AuthService _authService = AuthService();
  bool _isCheckingSession = true;
  Widget? _home;

  @override
  void initState() {
    super.initState();
    _initHome();
  }

  Future<void> _initHome() async {
    final isAuthenticated = await _authService.isAuthenticated();
    if (!mounted) return;

    if (isAuthenticated) {
      final role = await _authService.getStoredUserRole();
      final normalizedRole = role?.trim().toUpperCase();
      setState(() {
        _home = normalizedRole == 'ADMIN'
            ? const AdminDashboardScreen()
            : _authService.isDepartmentHeadRole(role)
                ? const DepartmentHeadDashboardScreen()
                : const WorkerChatScreen();
        _isCheckingSession = false;
      });
      return;
    }

    setState(() {
      _home = const LoginScreen();
      _isCheckingSession = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'ISL – Industrial Solutions Ltd.',
        debugShowCheckedModeBanner: false,
        // flutter_quill's editor/toolbar widgets look up
        // FlutterQuillLocalizations via the widget tree at build time --
        // without registering its delegate here (alongside the standard
        // Material/Widgets/Cupertino ones), any screen using QuillEditor
        // or QuillSimpleToolbar throws "UnimplementedError:
        // FlutterQuillLocalizations instance is required and could not
        // be found" (worker_create_document_screen.dart's editor).
        localizationsDelegates: const [
          quill.FlutterQuillLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.light,
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
          scaffoldBackgroundColor: AppColors.bgTop,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: AppColors.textDark,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.bgSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderLight),
            ),
          ),
        ),
        home: _isCheckingSession
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _home ?? const LoginScreen(),
      ),
    );
  }
}