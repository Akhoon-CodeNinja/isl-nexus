import 'package:flutter_test/flutter_test.dart';
import 'package:isl_app/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores auth session and reports authenticated state', () async {
    SharedPreferences.setMockInitialValues({});
    final service = AuthService();

    await service.storeUserSession({
      'access': 'access-token',
      'refresh': 'refresh-token',
      'role': 'WORKER',
    });

    expect(await service.isAuthenticated(), isTrue);
    expect(await service.getStoredUserRole(), 'WORKER');
  });
}
