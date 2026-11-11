import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unlock_core/unlock_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService & Payment Verification Tests', () {
    late AuthService authService;
    late DeviceInfo validIphone;
    late DeviceInfo differentIphone;
    late DeviceInfo unidentifiableIphone;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      authService = AuthService(
        websiteUrl: 'https://414unlock.pages.dev',
        apiUrl: 'https://api.example.com',
      );

      validIphone = DeviceInfo(
        platform: DevicePlatform.ios,
        name: 'iPhone 15 Pro',
        model: 'iPhone 15 Pro',
        serialNumber: 'C39Z1028N40V',
        statusDescription: 'USB Connected',
      );

      differentIphone = DeviceInfo(
        platform: DevicePlatform.ios,
        name: 'iPhone 14',
        model: 'iPhone 14',
        serialNumber: 'F2LZ8899K123',
        statusDescription: 'USB Connected',
      );

      unidentifiableIphone = DeviceInfo(
        platform: DevicePlatform.ios,
        name: 'Apple iPhone',
        statusDescription: 'USB Connected',
      );
    });

    test('Test 1: Session creation using detected serial number or IMEI', () async {
      // 1. Must be authenticated with approved ownership verification
      authService.setAuthenticatedSession(
        token: 'valid_jwt_token',
        user: const UserProfile(
          id: 'usr_1',
          fullName: 'Test Owner',
          email: 'owner@example.com',
          emailVerified: true,
        ),
      );
      authService.setVerificationState(VerificationState.approved);

      // 2. Mock API transport for POST /api/payments/session
      authService.httpTransportOverride = (method, uri, headers, body) async {
        expect(method, 'POST');
        expect(uri.path, '/api/payments/session');
        final authHeader = headers['authorization'] ?? headers['Authorization'];
        expect(authHeader, 'Bearer valid_jwt_token');

        // Verify request payload
        expect(body, contains('"deviceModel":"iPhone 15 Pro"'));
        expect(body, contains('"identifierKind":"serial"'));
        expect(body, contains('"identifier":"C39Z1028N40V"'));

        return {
          'ok': true,
          'sessionId': '0123456789abcdef0123456789abcdef',
          'launchToken': 'aabbccddeeff00112233445566778899aabbccddeeff0011',
          'paymentReference': '414U-ABC12345',
          'deviceModel': 'iPhone 15 Pro',
          'identifierKind': 'serial',
          'maskedIdentifier': '•••• •••• N40V',
          'status': 'pending',
          'expiresAt': 1900000000,
        };
      };

      final session = await authService.createPaymentSession(validIphone);

      expect(session, isNotNull);
      expect(session!.sessionId, '0123456789abcdef0123456789abcdef');
      expect(session.paymentReference, '414U-ABC12345');
      expect(session.maskedIdentifier, '•••• •••• N40V');
      expect(session.status, 'pending');
      expect(session.isVerified, false);
      expect(authService.isPaymentVerified, false);
      expect(authService.activePaymentSession, isNotNull);
    });

    test('Test 1b: Session creation with detected 15-digit IMEI', () async {
      authService.setAuthenticatedSession(
        token: 'valid_jwt_token',
        user: const UserProfile(id: 'usr_1', fullName: 'Owner', email: 'owner@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.approved);

      final imeiIphone = DeviceInfo(
        platform: DevicePlatform.ios,
        name: 'iPhone 13',
        serialNumber: '354890123456789',
        statusDescription: 'USB Connected',
      );

      expect(imeiIphone.detectedIdentifier?.$1, 'imei');
      expect(imeiIphone.identifierLabel, 'IMEI (masked)');
      expect(imeiIphone.maskedIdentifier, '•••• •••• 6789');

      authService.httpTransportOverride = (method, uri, headers, body) async {
        expect(body, contains('"identifierKind":"imei"'));
        expect(body, contains('"identifier":"354890123456789"'));
        return {
          'ok': true,
          'sessionId': 'session_imei_123',
          'launchToken': 'token_imei_123',
          'paymentReference': '414U-IMEI9999',
          'deviceModel': 'iPhone 13',
          'identifierKind': 'imei',
          'maskedIdentifier': '•••• •••• 6789',
          'status': 'pending',
          'expiresAt': 1900000000,
        };
      };

      final session = await authService.createPaymentSession(imeiIphone);
      expect(session, isNotNull);
      expect(session!.identifierKind, 'imei');
    });

    test('Test 2: Missing or malformed identifiers are rejected without fabrication', () async {
      authService.setAuthenticatedSession(
        token: 'valid_jwt_token',
        user: const UserProfile(id: 'u1', fullName: 'U', email: 'u@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.approved);

      // Unidentifiable device exposes no legitimate identifier
      expect(unidentifiableIphone.detectedIdentifier, isNull);
      expect(unidentifiableIphone.maskedIdentifier, 'Unavailable');

      final session = await authService.createPaymentSession(unidentifiableIphone);
      expect(session, isNull);
      expect(authService.errorMessage, contains('does not expose a recognized serial number, IMEI, or UDID'));
    });

    test('Test 2b: Unapproved account verification blocks payment session creation', () async {
      authService.setAuthenticatedSession(
        token: 'valid_jwt_token',
        user: const UserProfile(id: 'u1', fullName: 'U', email: 'u@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.pending);

      final session = await authService.createPaymentSession(validIphone);
      expect(session, isNull);
      expect(authService.errorMessage, contains('Account verification approval is required'));
    });

    test('Test 3: Browser sign-in and callback state validation prevents CSRF and replay', () async {
      authService.setActiveNonceForTest('legitimate_state_nonce_12345678');

      // Attempt callback with forged/mismatched nonce
      final forgedSuccess = await authService.handleAuthCallback(
        code: 'valid_handoff_code_1234567890abcdef1234567890abcdef',
        state: 'forged_state_nonce_99999999',
      );

      expect(forgedSuccess, false);
      expect(authService.status, AuthStatus.error);
      expect(authService.errorMessage, contains('Authentication state nonce validation failed'));

      // Replay attempt: nonce was consumed or cleared, second attempt rejected
      final replaySuccess = await authService.handleAuthCallback(
        code: 'valid_handoff_code_1234567890abcdef1234567890abcdef',
        state: 'legitimate_state_nonce_12345678',
      );
      expect(replaySuccess, false);
    });

    test('Test 4: Expired or already-used handoff codes are rejected by server', () async {
      authService.setActiveNonceForTest('valid_nonce_abc123');

      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/auth/redeem-app-code') {
          return {
            'ok': false,
            'error': 'INVALID_APP_CODE',
            'message': 'The sign-in code is invalid or expired. Start sign-in again.',
          };
        }
        throw Exception('Unexpected call: ${uri.path}');
      };

      final success = await authService.handleAuthCallback(
        code: 'expired_code_1234567890abcdef1234567890abcdef',
        state: 'valid_nonce_abc123',
      );

      expect(success, false);
      expect(authService.status, AuthStatus.error);
      expect(authService.errorMessage, contains('The sign-in code is invalid or expired'));
    });

    test('Test 5: Payment pending, verified, and expired states handled explicitly', () async {
      authService.setAuthenticatedSession(
        token: 'token_123',
        user: const UserProfile(id: 'u1', fullName: 'U', email: 'u@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.approved);

      // Create session
      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/payments/session') {
          return {
            'ok': true,
            'sessionId': 'session_001',
            'launchToken': 'l1',
            'paymentReference': '414U-1',
            'deviceModel': 'iPhone 15 Pro',
            'identifierKind': 'serial',
            'maskedIdentifier': '•••• •••• N40V',
            'status': 'pending',
            'expiresAt': 1900000000,
          };
        }
        return {};
      };
      await authService.createPaymentSession(validIphone);

      // A: Verify pending
      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/payments/status') {
          return {'ok': true, 'sessionId': 'session_001', 'status': 'pending', 'verified': false};
        }
        return {};
      };
      var valid = await authService.validatePaymentWithConnectedDevice(validIphone);
      expect(valid, false);
      expect(authService.isPaymentVerified, false);
      expect(authService.errorMessage, contains('Payment is pending confirmation'));

      // B: Verify expired
      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/payments/status') {
          return {'ok': true, 'sessionId': 'session_001', 'status': 'expired', 'verified': false};
        }
        return {};
      };
      valid = await authService.validatePaymentWithConnectedDevice(validIphone);
      expect(valid, false);
      expect(authService.isPaymentVerified, false);
      expect(authService.errorMessage, contains('This payment session has expired'));

      // C: Verify confirmed + device match
      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/payments/status') {
          return {'ok': true, 'sessionId': 'session_001', 'status': 'verified', 'verified': true};
        }
        if (uri.path == '/api/payments/validate-device') {
          return {'ok': true, 'authorized': true, 'status': 'verified', 'sessionId': 'session_001'};
        }
        return {};
      };
      valid = await authService.validatePaymentWithConnectedDevice(validIphone);
      expect(valid, true);
      expect(authService.isPaymentVerified, true);
      expect(authService.authorizedSessionId, 'session_001');
    });

    test('Test 6: Payment session mismatch rejects callback', () async {
      authService.setAuthenticatedSession(
        token: 'token_123',
        user: const UserProfile(id: 'u1', fullName: 'U', email: 'u@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.approved);

      // Active session in app is session_AAA
      authService.httpTransportOverride = (method, uri, headers, body) async {
        return {
          'ok': true,
          'sessionId': 'session_AAA',
          'launchToken': 'launch_AAA',
          'paymentReference': '414U-AAA',
          'deviceModel': 'iPhone 15 Pro',
          'identifierKind': 'serial',
          'maskedIdentifier': '•••• •••• N40V',
          'status': 'pending',
          'expiresAt': 1900000000,
        };
      };
      await authService.createPaymentSession(validIphone);

      // Browser returns with a DIFFERENT paymentSessionId session_BBB
      authService.setActiveNonceForTest('active_nonce_123');
      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/auth/redeem-app-code') {
          return {'ok': true, 'token': 'token_new', 'user': {'id': 'u1', 'email': 'u@example.com'}};
        }
        return {};
      };

      final success = await authService.handleAuthCallback(
        code: 'handoff_code_123',
        state: 'active_nonce_123',
        paymentSessionId: 'session_BBB', // MISMATCH!
        currentDevice: validIphone,
      );

      expect(success, false);
      expect(authService.isPaymentVerified, false);
      expect(authService.errorMessage, contains('Payment session mismatch'));
    });

    test('Test 7: Different device connected after payment is detected and blocked', () async {
      authService.setAuthenticatedSession(
        token: 'token_123',
        user: const UserProfile(id: 'u1', fullName: 'U', email: 'u@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.approved);

      // Paid session was created for validIphone (serial: C39Z1028N40V)
      authService.httpTransportOverride = (method, uri, headers, body) async {
        return {
          'ok': true,
          'sessionId': 'session_001',
          'launchToken': 'l1',
          'paymentReference': '414U-1',
          'deviceModel': 'iPhone 15 Pro',
          'identifierKind': 'serial',
          'maskedIdentifier': '•••• •••• N40V',
          'status': 'pending',
          'expiresAt': 1900000000,
        };
      };
      await authService.createPaymentSession(validIphone);

      // Backend reports verified payment, but validate-device receives differentIphone (F2LZ8899K123)
      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/payments/status') {
          return {'ok': true, 'sessionId': 'session_001', 'status': 'verified', 'verified': true};
        }
        if (uri.path == '/api/payments/validate-device') {
          // Server detects device mismatch and returns 403
          throw Exception('DEVICE_MISMATCH: The payment is not linked to the currently connected device.');
        }
        return {};
      };

      final valid = await authService.validatePaymentWithConnectedDevice(differentIphone);
      expect(valid, false);
      expect(authService.isPaymentVerified, false);
      expect(authService.errorMessage, contains('Device mismatch'));
    });

    test('Test 7b: Disconnecting authorized iPhone revokes payment authorization immediately', () async {
      // Put in verified state
      authService.setAuthenticatedSession(
        token: 'token_123',
        user: const UserProfile(id: 'u1', fullName: 'U', email: 'u@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.approved);

      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/payments/session') {
          return {
            'ok': true,
            'sessionId': 'session_001',
            'launchToken': 'l1',
            'paymentReference': '414U-1',
            'deviceModel': 'iPhone 15 Pro',
            'identifierKind': 'serial',
            'maskedIdentifier': '•••• •••• N40V',
            'status': 'pending',
            'expiresAt': 1900000000,
          };
        }
        if (uri.path == '/api/payments/status') {
          return {'ok': true, 'sessionId': 'session_001', 'status': 'verified', 'verified': true};
        }
        if (uri.path == '/api/payments/validate-device') {
          return {'ok': true, 'authorized': true, 'status': 'verified', 'sessionId': 'session_001'};
        }
        return {};
      };

      await authService.createPaymentSession(validIphone);
      await authService.validatePaymentWithConnectedDevice(validIphone);
      expect(authService.isPaymentVerified, true);
      expect(authService.isEligibleForService, true);

      // Case A: User unplugs the cable!
      authService.onConnectedDeviceChanged(null);
      expect(authService.isPaymentVerified, false);
      expect(authService.isEligibleForService, false);
      expect(authService.errorMessage, contains('iPhone disconnected'));

      // Re-validate to verified state
      await authService.validatePaymentWithConnectedDevice(validIphone);
      expect(authService.isPaymentVerified, true);

      // Case B: User connects a different device while verified!
      authService.onConnectedDeviceChanged(differentIphone);
      expect(authService.isPaymentVerified, false);
      expect(authService.isEligibleForService, false);
      expect(authService.errorMessage, contains('Different device connected'));
    });

    test('Test 8: Network failure and unconfigured payment provider fail safely', () async {
      authService.setAuthenticatedSession(
        token: 'token_123',
        user: const UserProfile(id: 'u1', fullName: 'U', email: 'u@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.approved);

      // Unconfigured API URL
      authService.configureUrls(apiUrl: '');
      final sess = await authService.createPaymentSession(validIphone);
      expect(sess, isNull);
      expect(authService.errorMessage, contains('API is not configured'));

      // Network connection failure
      authService.configureUrls(apiUrl: 'https://api.example.com');
      authService.httpTransportOverride = (method, uri, headers, body) async {
        throw Exception('SocketException: Connection refused');
      };

      final failSess = await authService.createPaymentSession(validIphone);
      expect(failSess, isNull);
      expect(authService.errorMessage, contains('Connection refused'));
    });

    test('Test 9: Successful continuation only after backend confirms payment and device match', () async {
      authService.setAuthenticatedSession(
        token: 'token_123',
        user: const UserProfile(id: 'u1', fullName: 'U', email: 'u@example.com', emailVerified: true),
      );
      authService.setVerificationState(VerificationState.approved);

      // Not verified yet -> not eligible
      expect(authService.isEligibleForService, false);

      // Session created
      authService.httpTransportOverride = (method, uri, headers, body) async {
        return {
          'ok': true,
          'sessionId': 'session_MATCH',
          'launchToken': 'launch_MATCH',
          'paymentReference': '414U-MATCH',
          'deviceModel': 'iPhone 15 Pro',
          'identifierKind': 'serial',
          'maskedIdentifier': '•••• •••• N40V',
          'status': 'pending',
          'expiresAt': 1900000000,
        };
      };
      await authService.createPaymentSession(validIphone);
      expect(authService.isEligibleForService, false);

      // Backend confirms status verified AND validate-device confirms match
      authService.httpTransportOverride = (method, uri, headers, body) async {
        if (uri.path == '/api/payments/status') {
          return {'ok': true, 'sessionId': 'session_MATCH', 'status': 'verified', 'verified': true};
        }
        if (uri.path == '/api/payments/validate-device') {
          return {'ok': true, 'authorized': true, 'status': 'verified', 'sessionId': 'session_MATCH'};
        }
        return {};
      };

      final confirmed = await authService.validatePaymentWithConnectedDevice(validIphone);
      expect(confirmed, true);
      expect(authService.isPaymentVerified, true);
      expect(authService.isEligibleForService, true);
    });
  });
}
