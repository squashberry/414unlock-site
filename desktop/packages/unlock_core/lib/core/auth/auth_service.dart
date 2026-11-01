import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../device/device_info.dart';
import '../logging/app_logger.dart';
import '../prerequisites/windows_checker_helper.dart';

enum AuthStatus {
  unauthenticated,
  signingIn,
  authenticated,
  error,
}

enum VerificationState {
  notSubmitted,
  pending,
  approved,
  rejected,
  unknown,
}

class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final bool emailVerified;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.emailVerified,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      emailVerified: json['emailVerified'] == true,
    );
  }
}

class PaymentSessionInfo {
  final String sessionId;
  final String launchToken;
  final String paymentReference;
  final String deviceModel;
  final String identifierKind;
  final String maskedIdentifier;
  String status;
  final int expiresAt;
  final String? expectedIdentifier; // In-memory only; never logged or put in query params
  final String? expectedIdentifierKind;
  String? stateNonce;

  PaymentSessionInfo({
    required this.sessionId,
    required this.launchToken,
    required this.paymentReference,
    required this.deviceModel,
    required this.identifierKind,
    required this.maskedIdentifier,
    required this.status,
    required this.expiresAt,
    this.expectedIdentifier,
    this.expectedIdentifierKind,
    this.stateNonce,
  });

  factory PaymentSessionInfo.fromJson(
    Map<String, dynamic> json, {
    String? expectedIdentifier,
    String? expectedIdentifierKind,
    String? stateNonce,
  }) {
    return PaymentSessionInfo(
      sessionId: json['sessionId']?.toString() ?? '',
      launchToken: json['launchToken']?.toString() ?? '',
      paymentReference: json['paymentReference']?.toString() ?? '',
      deviceModel: json['deviceModel']?.toString() ?? '',
      identifierKind: json['identifierKind']?.toString() ?? 'serial',
      maskedIdentifier: json['maskedIdentifier']?.toString() ?? '•••• •••• ••••',
      status: json['status']?.toString() ?? 'pending',
      expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
      expectedIdentifier: expectedIdentifier,
      expectedIdentifierKind: expectedIdentifierKind,
      stateNonce: stateNonce,
    );
  }

  bool get isVerified => status == 'verified';
  bool get isExpired =>
      status == 'expired' ||
      (expiresAt > 0 && DateTime.now().millisecondsSinceEpoch ~/ 1000 > expiresAt);
}

class AuthService extends ChangeNotifier {
  static const String defaultWebsiteBaseUrl =
      'https://squashberry.github.io/414unlock-site';
  static const String defaultApiBaseUrl = ''; // will be read from site-config or config

  static const String _kAuthToken = 'auth_jwt_token';
  static const String _kUserProfile = 'auth_user_profile';

  AuthStatus _status = AuthStatus.unauthenticated;
  String _websiteBaseUrl = defaultWebsiteBaseUrl;
  String _apiBaseUrl = defaultApiBaseUrl;
  String? _token;
  UserProfile? _user;
  VerificationState _verificationState = VerificationState.unknown;
  String _verificationNote = '';
  bool _isPaymentVerified = false;
  String _errorMessage = '';
  bool _autoDiscoverApiUrl = true;

  PaymentSessionInfo? _activePaymentSession;
  String? _authorizedSessionId;
  DeviceInfo? Function()? currentDeviceGetter;

  String? _activeNonce;
  HttpServer? _loopbackServer;
  Timer? _authTimeoutTimer;

  // Custom HTTP transport handler for testability
  Future<Map<String, dynamic>> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  )? httpTransportOverride;

  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated && _token != null;
  UserProfile? get user => _user;
  VerificationState get verificationState => _verificationState;
  String get verificationNote => _verificationNote;
  bool get isPaymentVerified => _isPaymentVerified;
  String get errorMessage => _errorMessage;
  String get websiteBaseUrl => _websiteBaseUrl;
  String get apiBaseUrl => _apiBaseUrl;
  PaymentSessionInfo? get activePaymentSession => _activePaymentSession;
  String? get authorizedSessionId => _authorizedSessionId;
  String? get activeNonce => _activeNonce;

  bool get isEligibleForService =>
      isAuthenticated &&
      _verificationState == VerificationState.approved &&
      _isPaymentVerified;

  AuthService({String? websiteUrl, String? apiUrl, bool autoDiscoverApiUrl = true}) {
    _autoDiscoverApiUrl = autoDiscoverApiUrl;
    if (websiteUrl != null && websiteUrl.isNotEmpty) {
      _websiteBaseUrl = websiteUrl.replaceAll(RegExp(r'/+$'), '');
    }
    if (apiUrl != null) {
      _apiBaseUrl = apiUrl.replaceAll(RegExp(r'/+$'), '');
      if (apiUrl.isEmpty) {
        _autoDiscoverApiUrl = false;
      }
    }
  }

  void configureUrls({String? websiteUrl, String? apiUrl, bool? autoDiscoverApiUrl}) {
    if (websiteUrl != null && websiteUrl.isNotEmpty) {
      _websiteBaseUrl = websiteUrl.replaceAll(RegExp(r'/+$'), '');
    }
    if (apiUrl != null) {
      _apiBaseUrl = apiUrl.replaceAll(RegExp(r'/+$'), '');
      if (apiUrl.isEmpty) {
        _autoDiscoverApiUrl = false;
      }
    }
    if (autoDiscoverApiUrl != null) {
      _autoDiscoverApiUrl = autoDiscoverApiUrl;
    }
    notifyListeners();
  }

  /// Restores persistent session token if available
  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString(_kAuthToken);
      final storedUserJson = prefs.getString(_kUserProfile);

      if (storedToken != null && storedToken.isNotEmpty) {
        _token = storedToken;
        if (storedUserJson != null) {
          try {
            _user = UserProfile.fromJson(jsonDecode(storedUserJson));
          } catch (_) {}
        }
        _status = AuthStatus.authenticated;
        notifyListeners();

        // Refresh live account status and verification state from backend
        await refreshAccountStatus();
      }
    } catch (e) {
      AppLogger().warning('Could not restore auth session: $e');
    }
  }

  /// Sets authenticated credentials directly (useful for tests or token handoffs)
  void setAuthenticatedSession({required String token, required UserProfile user}) {
    _token = token;
    _user = user;
    _status = AuthStatus.authenticated;
    _errorMessage = '';
    notifyListeners();
  }

  /// Sets verification state directly (useful for tests)
  void setVerificationState(VerificationState state, {String note = ''}) {
    _verificationState = state;
    _verificationNote = note;
    notifyListeners();
  }

  /// Begins sign-in flow by opening website with random nonce and loopback listener
  Future<void> startWebSignIn({bool isSignUp = false}) async {
    _status = AuthStatus.signingIn;
    _errorMessage = '';
    notifyListeners();

    // 1. Generate cryptographically random single-use nonce
    _activeNonce = _generateNonce();

    // 2. Start local loopback HTTP server
    final port = await _startLoopbackServer();

    // 3. Register custom URI scheme 414unlock:// for current Windows user
    _registerWindowsUriScheme();

    // 4. Construct website authentication URL
    final flow = isSignUp ? 'signup' : 'signin';
    final callbackUrl = port != null
        ? 'http://127.0.0.1:$port/auth/callback'
        : '414unlock://auth/callback';

    final uri = Uri.parse('$_websiteBaseUrl/account.html').replace(
      queryParameters: {
        'flow': flow,
        'return': 'app',
        'state': _activeNonce!,
        'callback': callbackUrl,
      },
    );

    AppLogger().info('Launching browser for official website authentication: flow=$flow');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Cannot launch default web browser');
      }

      // Timeout after 8 minutes if user does not complete authentication
      _authTimeoutTimer?.cancel();
      _authTimeoutTimer = Timer(const Duration(minutes: 8), () {
        if (_status == AuthStatus.signingIn) {
          _cancelAuth('Sign-in session timed out. Please try again.');
        }
      });
    } catch (e) {
      _cancelAuth('Failed to open web browser: $e');
    }
  }

  /// Checks if the connected device (by serial number or IMEI) has already been registered
  /// and paid on the 414Unlock website. If already paid, automatically bypasses checkout.
  Future<bool> checkExistingDevicePayment(DeviceInfo device) async {
    final identPair = device.detectedIdentifier;
    if (identPair == null) return false;
    final kind = identPair.$1;
    final ident = identPair.$2;

    if (!isAuthenticated || _token == null) return false;

    await _ensureApiBaseUrl();
    if (_apiBaseUrl.isEmpty) return false;

    try {
      final uri = Uri.parse('$_apiBaseUrl/api/payments/check-device').replace(
        queryParameters: {
          'identifier': ident,
          'identifierKind': kind,
        },
      );
      final data = await _executeRequest(
        'GET',
        uri,
        {HttpHeaders.authorizationHeader: 'Bearer $_token'},
        null,
      );

      if (data['paid'] == true || data['status'] == 'verified' || data['authorized'] == true) {
        final sessionId = data['sessionId']?.toString() ??
            'paid_${ident.substring(max(0, ident.length - 6))}';
        _activePaymentSession = PaymentSessionInfo(
          sessionId: sessionId,
          launchToken: data['launchToken']?.toString() ?? 'bypass_token',
          paymentReference: data['paymentReference']?.toString() ?? 'PAID_PREVIOUSLY',
          deviceModel: device.modelName,
          identifierKind: kind,
          maskedIdentifier: device.maskedIdentifier,
          status: 'verified',
          expiresAt: DateTime.now().add(const Duration(hours: 48)).millisecondsSinceEpoch ~/ 1000,
          expectedIdentifier: ident,
          expectedIdentifierKind: kind,
        );
        _isPaymentVerified = true;
        _authorizedSessionId = sessionId;
        _errorMessage = '';
        AppLogger().info(
          'Existing valid payment found for ${device.modelName} (${device.maskedIdentifier}). Bypassing checkout for retry.',
        );
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger().info('Existing device payment check: $e');
      return false;
    }
  }

  /// Creates a device-bound payment session on the website API: POST /api/payments/session
  Future<PaymentSessionInfo?> createPaymentSession(DeviceInfo device) async {
    _errorMessage = '';

    // 0. Auto-bypass check: check if device was already paid on website
    final alreadyPaid = await checkExistingDevicePayment(device);
    if (alreadyPaid && _activePaymentSession != null) {
      return _activePaymentSession;
    }

    // 1. Confirm account is authenticated
    if (!isAuthenticated || _token == null) {
      _errorMessage = 'Authentication required. Sign in with your 414Unlock account first.';
      AppLogger().warning(_errorMessage);
      notifyListeners();
      return null;
    }

    // 2. Confirm backend reports required account verification approval
    if (_verificationState != VerificationState.approved) {
      _errorMessage =
          'Account verification approval is required before creating a payment session. Complete ownership verification on the website.';
      AppLogger().warning(_errorMessage);
      notifyListeners();
      return null;
    }

    // 3. Extract actual detected device identifier without fabrication
    final identPair = device.detectedIdentifier;
    if (identPair == null) {
      _errorMessage =
          'The connected device does not expose a recognized serial number, IMEI, or UDID. Ensure the device is powered on and trusted.';
      AppLogger().warning('Cannot create payment session: device identifier missing or malformed');
      notifyListeners();
      return null;
    }

    final kind = identPair.$1;
    final ident = identPair.$2;

    await _ensureApiBaseUrl();
    if (_apiBaseUrl.isEmpty) {
      _errorMessage = 'The 414Unlock API is not configured. Update site-config.js or API configuration.';
      AppLogger().warning(_errorMessage);
      notifyListeners();
      return null;
    }

    try {
      final uri = Uri.parse('$_apiBaseUrl/api/payments/session');
      final headers = {
        HttpHeaders.authorizationHeader: 'Bearer $_token',
        HttpHeaders.contentTypeHeader: 'application/json',
      };
      final body = jsonEncode({
        'deviceModel': device.modelName,
        'identifierKind': kind,
        'identifier': ident,
      });

      final data = await _executeRequest('POST', uri, headers, body);

      if (data['ok'] != true || data['sessionId'] == null) {
        throw Exception(data['message'] ?? data['error'] ?? 'Server rejected payment session creation');
      }

      final session = PaymentSessionInfo.fromJson(
        data,
        expectedIdentifier: ident,
        expectedIdentifierKind: kind,
      );

      _activePaymentSession = session;
      _isPaymentVerified = false;

      // Log only masked identifier for privacy
      AppLogger().info(
        'Created device-bound payment session for ${device.modelName} (ref: ${session.paymentReference}, masked: ${session.maskedIdentifier})',
      );
      notifyListeners();
      return session;
    } catch (e) {
      _errorMessage = 'Could not create payment session: $e';
      AppLogger().error('Payment session creation failed', e.toString());
      notifyListeners();
      return null;
    }
  }

  /// Opens the payment checkout page in the system browser
  Future<void> openPaymentWebsite({PaymentSessionInfo? session}) async {
    final active = session ?? _activePaymentSession;
    if (active == null) {
      _errorMessage = 'No active payment session to open. Create a payment session first.';
      notifyListeners();
      return;
    }

    // Generate fresh state nonce
    _activeNonce = _generateNonce();
    active.stateNonce = _activeNonce;

    final port = await _startLoopbackServer();
    final callbackUrl = port != null
        ? 'http://127.0.0.1:$port/auth/callback'
        : '414unlock://auth/callback';

    final paymentUri = Uri.parse('$_websiteBaseUrl/payment.html').replace(
      queryParameters: {
        'launch': active.launchToken,
        'state': _activeNonce!,
        'callback': callbackUrl,
      },
    );

    AppLogger().info(
      'Opening system browser for payment: model=${active.deviceModel}, ref=${active.paymentReference}, masked=${active.maskedIdentifier}',
    );

    try {
      if (await canLaunchUrl(paymentUri)) {
        await launchUrl(paymentUri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Cannot launch default web browser');
      }

      // Timeout payment session return after 15 minutes
      _authTimeoutTimer?.cancel();
      _authTimeoutTimer = Timer(const Duration(minutes: 15), () {
        if (_activeNonce != null) {
          _activeNonce = null;
          _stopLoopbackServer();
          AppLogger().info('Payment wait timeout expired');
        }
      });
    } catch (e) {
      _errorMessage = 'Failed to open web browser: $e';
      AppLogger().error('Failed to open payment browser', e.toString());
      notifyListeners();
    }
  }

  /// Handles incoming callback parameters from loopback server or custom URI
  Future<bool> handleAuthCallback({
    required String code,
    required String state,
    String? paymentSessionId,
    DeviceInfo? currentDevice,
  }) async {
    AppLogger().info('Processing authentication return callback');

    // 1. Nonce validation
    if (_activeNonce == null || state.isEmpty || state != _activeNonce) {
      _cancelAuth('Authentication state nonce validation failed. Potential replay or CSRF.');
      AppLogger().error('Authentication denied: State nonce mismatch or expired');
      return false;
    }

    _activeNonce = null; // single-use consume
    _authTimeoutTimer?.cancel();
    await _stopLoopbackServer();

    // 2. Resolve API base URL if not set
    await _ensureApiBaseUrl();

    if (_apiBaseUrl.isEmpty) {
      _status = AuthStatus.error;
      _errorMessage =
          'The authentication service API is not configured. Deploy the 414Unlock Worker API and update site-config.js.';
      AppLogger().warning(_errorMessage);
      notifyListeners();
      return false;
    }

    // 3. Redeem the one-time handoff code with the backend
    try {
      final redeemUri = Uri.parse('$_apiBaseUrl/api/auth/redeem-app-code');
      final data = await _executeRequest(
        'POST',
        redeemUri,
        {HttpHeaders.contentTypeHeader: 'application/json'},
        jsonEncode({'code': code}),
      );

      if (data['ok'] != true || data['token'] == null) {
        throw Exception(data['message'] ?? data['error'] ?? 'Code redemption rejected by server');
      }

      _token = data['token'] as String;
      if (data['user'] is Map<String, dynamic>) {
        _user = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
      }

      _status = AuthStatus.authenticated;
      AppLogger().info('Authentication successful for: ${_user?.email ?? "User"}');

      // Persist session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAuthToken, _token!);
      if (_user != null) {
        await prefs.setString(
          _kUserProfile,
          jsonEncode({
            'id': _user!.id,
            'fullName': _user!.fullName,
            'email': _user!.email,
            'emailVerified': _user!.emailVerified,
          }),
        );
      }

      // 4. If callback contains paymentSessionId, validate the payment session
      if (paymentSessionId != null && paymentSessionId.isNotEmpty) {
        if (_activePaymentSession == null || _activePaymentSession!.sessionId != paymentSessionId) {
          _errorMessage =
              'Payment session mismatch. The returned payment session ID ($paymentSessionId) does not match the active session (${_activePaymentSession?.sessionId}).';
          AppLogger().error(_errorMessage);
          _isPaymentVerified = false;
          notifyListeners();
          return false;
        }

        // Independently validate payment and match with connected device
        final dev = currentDevice ?? currentDeviceGetter?.call();
        final validated = await validatePaymentWithConnectedDevice(dev);
        return validated;
      }

      // Refresh account & verification status
      await refreshAccountStatus();
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = 'Could not redeem sign-in code: $e';
      AppLogger().error('Code redemption error', e.toString());
      notifyListeners();
      return false;
    }
  }

  /// Handles custom protocol URI (e.g. 414unlock://auth/callback?code=...&state=...&paymentSessionId=...)
  Future<bool> handleProtocolUri(Uri uri, {DeviceInfo? currentDevice}) async {
    final code = uri.queryParameters['code'] ?? '';
    final state = uri.queryParameters['state'] ?? '';
    final paymentSessionId = uri.queryParameters['paymentSessionId'];
    if (code.isEmpty || state.isEmpty) return false;
    return await handleAuthCallback(
      code: code,
      state: state,
      paymentSessionId: paymentSessionId,
      currentDevice: currentDevice,
    );
  }

  /// Independently validates the payment with the backend and confirms device match
  Future<bool> validatePaymentWithConnectedDevice(DeviceInfo? currentDevice) async {
    final session = _activePaymentSession;
    if (session == null) {
      _isPaymentVerified = false;
      _errorMessage = 'No active payment session to validate.';
      notifyListeners();
      return false;
    }

    if (_token == null || _token!.isEmpty) {
      _isPaymentVerified = false;
      _errorMessage = 'Authentication required. Sign in first.';
      notifyListeners();
      return false;
    }

    await _ensureApiBaseUrl();
    if (_apiBaseUrl.isEmpty) {
      _isPaymentVerified = false;
      _errorMessage = 'The 414Unlock API is not configured.';
      notifyListeners();
      return false;
    }

    try {
      // Step 1: GET /api/payments/status?sessionId=<sessionId>
      final statusUri = Uri.parse('$_apiBaseUrl/api/payments/status?sessionId=${session.sessionId}');
      final statusData = await _executeRequest(
        'GET',
        statusUri,
        {HttpHeaders.authorizationHeader: 'Bearer $_token'},
        null,
      );

      final serverStatus = statusData['status']?.toString() ?? 'pending';
      session.status = serverStatus;

      if (serverStatus == 'pending') {
        _isPaymentVerified = false;
        _errorMessage =
            'Payment is pending confirmation. Complete checkout in SquashberryPay and verify your confirmation code.';
        notifyListeners();
        return false;
      }

      if (serverStatus == 'expired') {
        _isPaymentVerified = false;
        _errorMessage = 'This payment session has expired. Please create a new payment session.';
        notifyListeners();
        return false;
      }

      if (serverStatus != 'verified' || statusData['verified'] != true) {
        _isPaymentVerified = false;
        _errorMessage = 'Payment has not been confirmed by the server.';
        notifyListeners();
        return false;
      }

      // Step 2: Confirm currently connected device is present
      if (currentDevice == null) {
        _isPaymentVerified = false;
        _errorMessage = 'Device disconnected. Reconnect your iPhone to complete payment validation.';
        notifyListeners();
        return false;
      }

      // Step 3: Re-read hardware identifier from currently connected device
      final currentIdentPair = currentDevice.detectedIdentifier;
      if (currentIdentPair == null) {
        _isPaymentVerified = false;
        _errorMessage = 'Could not read a valid identifier from the connected iPhone.';
        notifyListeners();
        return false;
      }

      final currentKind = currentIdentPair.$1;
      final currentIdent = currentIdentPair.$2;

      // Check if identifier kind matches session kind
      if (currentKind != session.expectedIdentifierKind && session.expectedIdentifierKind != null) {
        _isPaymentVerified = false;
        _errorMessage =
            'Device mismatch: The connected iPhone exposes identifier kind "$currentKind", but this session is bound to "${session.expectedIdentifierKind}".';
        notifyListeners();
        return false;
      }

      // Step 4: POST /api/payments/validate-device
      final validateUri = Uri.parse('$_apiBaseUrl/api/payments/validate-device');
      final validateData = await _executeRequest(
        'POST',
        validateUri,
        {
          HttpHeaders.authorizationHeader: 'Bearer $_token',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        jsonEncode({
          'sessionId': session.sessionId,
          'identifierKind': currentKind,
          'identifier': currentIdent,
        }),
      );

      if (validateData['authorized'] != true || validateData['status'] != 'verified') {
        throw Exception(validateData['message'] ?? 'Device validation rejected by server');
      }

      // Step 5: Confirmed!
      _isPaymentVerified = true;
      session.status = 'verified';
      _authorizedSessionId = session.sessionId;
      _errorMessage = '';
      AppLogger().info(
        'Payment and connected device successfully validated: ${currentDevice.modelName} (${currentDevice.maskedIdentifier})',
      );
      notifyListeners();
      return true;
    } catch (e) {
      _isPaymentVerified = false;
      final errStr = e.toString();
      if (errStr.contains('DEVICE_MISMATCH') || errStr.contains('not linked to the currently connected device')) {
        _errorMessage =
            'Device mismatch: The connected iPhone does not match the device linked to this payment session. Reconnect the original device or start a new payment session.';
      } else {
        _errorMessage = 'Payment validation error: $e';
      }
      AppLogger().error('Device payment validation failed', _errorMessage);
      notifyListeners();
      return false;
    }
  }

  /// Observes USB hardware changes to prevent payment authorization leak
  void onConnectedDeviceChanged(DeviceInfo? newDevice) {
    if (_isPaymentVerified) {
      if (newDevice == null) {
        _isPaymentVerified = false;
        _errorMessage = 'iPhone disconnected. Reconnect the authorized device to continue.';
        AppLogger().warning('Authorized device unplugged — revoking active payment authorization');
        notifyListeners();
      } else {
        final pair = newDevice.detectedIdentifier;
        if (pair == null || pair.$2 != _activePaymentSession?.expectedIdentifier) {
          _isPaymentVerified = false;
          _errorMessage =
              'Different device connected (${newDevice.modelName}). Reconnect the authorized iPhone (${_activePaymentSession?.maskedIdentifier}) or create a new payment session.';
          AppLogger().warning('Device swap detected — revoking active payment authorization');
          notifyListeners();
        }
      }
    }
  }

  /// Refreshes user details and verification status from server
  Future<void> refreshAccountStatus() async {
    if (_token == null || _token!.isEmpty) return;
    await _ensureApiBaseUrl();
    if (_apiBaseUrl.isEmpty) return;

    try {
      // 1. Check user profile /me
      final meUri = Uri.parse('$_apiBaseUrl/api/auth/me');
      final meData = await _executeRequest(
        'GET',
        meUri,
        {HttpHeaders.authorizationHeader: 'Bearer $_token'},
        null,
      );
      if (meData['user'] is Map<String, dynamic>) {
        _user = UserProfile.fromJson(meData['user'] as Map<String, dynamic>);
      }

      // 2. Check verification status
      final verUri = Uri.parse('$_apiBaseUrl/api/verification/status');
      final verData = await _executeRequest(
        'GET',
        verUri,
        {HttpHeaders.authorizationHeader: 'Bearer $_token'},
        null,
      );
      final statusStr = verData['status']?.toString() ?? '';
      _verificationNote = verData['note']?.toString() ?? '';

      switch (statusStr) {
        case 'approved':
          _verificationState = VerificationState.approved;
          break;
        case 'pending':
          _verificationState = VerificationState.pending;
          break;
        case 'rejected':
          _verificationState = VerificationState.rejected;
          break;
        case 'not_submitted':
          _verificationState = VerificationState.notSubmitted;
          break;
        default:
          _verificationState = VerificationState.unknown;
          break;
      }

      // 3. If there is an active payment session, check its status
      if (_activePaymentSession != null) {
        final dev = currentDeviceGetter?.call();
        await validatePaymentWithConnectedDevice(dev);
      }

      AppLogger().info(
        'Account state refreshed: Email=${_user?.email}, Verification=${_verificationState.name}, Paid=$_isPaymentVerified',
      );
      notifyListeners();
    } catch (e) {
      AppLogger().warning('Failed to refresh server account status: $e');
    }
  }

  /// Executes an HTTP request using custom transport if supplied, else dart:io HttpClient
  Future<Map<String, dynamic>> _executeRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    if (httpTransportOverride != null) {
      return await httpTransportOverride!(method, uri, headers, body);
    }

    final client = HttpClient();
    final HttpClientRequest req;
    if (method == 'POST') {
      req = await client.postUrl(uri);
    } else if (method == 'GET') {
      req = await client.getUrl(uri);
    } else {
      req = await client.openUrl(method, uri);
    }

    headers.forEach((k, v) => req.headers.set(k, v));
    if (body != null) {
      req.write(body);
    }

    final response = await req.close();
    final respBody = await response.transform(utf8.decoder).join();
    final data = jsonDecode(respBody) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      final code = data['error'] ?? data['code'] ?? 'HTTP_${response.statusCode}';
      final msg = data['message'] ?? 'Server returned status ${response.statusCode}';
      throw Exception('$code: $msg');
    }

    return data;
  }

  /// Signs out and removes stored token
  Future<void> signOut() async {
    _token = null;
    _user = null;
    _verificationState = VerificationState.unknown;
    _isPaymentVerified = false;
    _activePaymentSession = null;
    _authorizedSessionId = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = '';

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuthToken);
    await prefs.remove(_kUserProfile);

    AppLogger().info('User signed out of 414Unlock');
    notifyListeners();
  }

  void _cancelAuth(String error) {
    _status = AuthStatus.error;
    _errorMessage = error;
    _activeNonce = null;
    _stopLoopbackServer();
    notifyListeners();
  }

  /// Generates a cryptographically secure random nonce
  String _generateNonce() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Sets active nonce for tests
  void setActiveNonceForTest(String? nonce) {
    _activeNonce = nonce;
  }

  /// Starts an ephemeral local HTTP loopback server to receive the browser callback
  Future<int?> _startLoopbackServer() async {
    await _stopLoopbackServer();
    try {
      _loopbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _loopbackServer!.port;
      AppLogger().info('Loopback authentication callback listening on port $port');

      _loopbackServer!.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (path == '/auth/callback' || path == '/') {
          final code = request.uri.queryParameters['code'] ?? '';
          final state = request.uri.queryParameters['state'] ?? '';
          final paymentSessionId = request.uri.queryParameters['paymentSessionId'];

          // Respond with clean web page
          request.response.headers.contentType = ContentType.html;
          request.response.write(r'''
            <!doctype html>
            <html lang="en">
            <head><meta charset="utf-8"><title>Return to 414Unlock</title>
            <style>
              body { background: #0F141C; color: #E6EDF3; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
              .card { background: #161D2A; border: 1px solid #2B3545; border-radius: 14px; padding: 36px 48px; text-align: center; max-width: 420px; box-shadow: 0 12px 32px rgba(0,0,0,0.5); }
              .badge { display: inline-flex; width: 48px; height: 48px; border-radius: 50%; background: rgba(34,197,94,0.15); color: #22C55E; align-items: center; justify-content: center; font-size: 24px; margin-bottom: 16px; }
              h2 { margin: 0 0 8px 0; font-size: 20px; }
              p { color: #8B98A9; font-size: 14px; margin: 0; }
            </style>
            </head>
            <body>
              <div class="card">
                <div class="badge">✓</div>
                <h2>Return to 414Unlock</h2>
                <p>You can close this tab and return to the 414Unlock desktop application.</p>
              </div>
            </body>
            </html>
          ''');
          await request.response.close();

          if (code.isNotEmpty && state.isNotEmpty) {
            await handleAuthCallback(
              code: code,
              state: state,
              paymentSessionId: paymentSessionId,
              currentDevice: currentDeviceGetter?.call(),
            );
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });

      return port;
    } catch (e) {
      AppLogger().warning('Could not start loopback auth server: $e');
      return null;
    }
  }

  Future<void> _stopLoopbackServer() async {
    if (_loopbackServer != null) {
      try {
        await _loopbackServer!.close(force: true);
      } catch (_) {}
      _loopbackServer = null;
    }
  }

  /// Registers 414unlock:// custom protocol for current Windows user
  void _registerWindowsUriScheme() {
    if (!Platform.isWindows) return;
    try {
      final exePath = Platform.resolvedExecutable;
      WindowsCheckerHelper.runPowerShell(
        '''
        \$regPath = "HKCU:\\Software\\Classes\\414unlock"
        New-Item -Path \$regPath -Force | Out-Null
        Set-ItemProperty -Path \$regPath -Name "(default)" -Value "URL:414Unlock Protocol"
        Set-ItemProperty -Path \$regPath -Name "URL Protocol" -Value ""
        New-Item -Path "\$regPath\\shell\\open\\command" -Force | Out-Null
        Set-ItemProperty -Path "\$regPath\\shell\\open\\command" -Name "(default)" -Value '"$exePath" "%1"'
        ''',
        timeoutSeconds: 3,
      );
    } catch (_) {}
  }

  Future<void> _ensureApiBaseUrl() async {
    if (!_autoDiscoverApiUrl) return;
    if (httpTransportOverride != null) return;
    if (_apiBaseUrl.isNotEmpty) return;
    if (_websiteBaseUrl.isEmpty) return;
    try {
      final client = HttpClient();
      final configReq = await client.getUrl(Uri.parse('$_websiteBaseUrl/site-config.js'));
      final configRes = await configReq.close();
      if (configRes.statusCode == HttpStatus.ok) {
        final text = await configRes.transform(utf8.decoder).join();
        final match = RegExp(r'''API_BASE_URL:\s*["']([^"']*)["']''').firstMatch(text);
        if (match != null && match.group(1)!.isNotEmpty) {
          _apiBaseUrl = match.group(1)!.replaceAll(RegExp(r'/+$'), '');
          AppLogger().info('Discovered API_BASE_URL from website: $_apiBaseUrl');
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _authTimeoutTimer?.cancel();
    _stopLoopbackServer();
    super.dispose();
  }
}
