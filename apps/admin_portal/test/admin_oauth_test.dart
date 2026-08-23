import 'package:admin_portal/auth/admin_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('adminPortalOAuthRedirectTo', () {
    test('keeps origin and port, drops fragment tokens', () {
      final uri = Uri.parse(
        'http://localhost:1234/#access_token=secret&refresh_token=r',
      );
      expect(adminPortalOAuthRedirectTo(uri), 'http://localhost:1234/');
    });

    test('drops query string', () {
      final uri = Uri.parse(
        'https://admin.example.com/login?code=abc#error=access_denied',
      );
      expect(adminPortalOAuthRedirectTo(uri), 'https://admin.example.com/');
    });

    test('omits default https port', () {
      expect(
        adminPortalOAuthRedirectTo(Uri.parse('https://admin.example.com:443/')),
        'https://admin.example.com/',
      );
    });
  });

  group('oauthErrorFromUri', () {
    test('reads error_description from query', () {
      final uri = Uri.parse(
        'http://localhost:1234/?error=access_denied&error_description=User+cancelled',
      );
      expect(oauthErrorFromUri(uri), 'User cancelled');
    });

    test('reads error from fragment', () {
      final uri = Uri.parse(
        'http://localhost:1234/#error=server_error&error_description=Provider+error',
      );
      expect(oauthErrorFromUri(uri), 'Provider error');
    });

    test('ignores session fragments without error', () {
      final uri = Uri.parse(
        'http://localhost:1234/#access_token=secret&expires_in=3600',
      );
      expect(oauthErrorFromUri(uri), isNull);
    });
  });
}
