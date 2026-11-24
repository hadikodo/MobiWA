import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import 'db.dart';
import 'device.dart';
import 'models.dart';

/// Sign-in, the current profile, and the admin user-management calls.
class Auth {
  Auth._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// The signed-in user's profile, or null when signed out.
  static final ValueNotifier<Profile?> profile = ValueNotifier(null);

  static bool get isAdmin => profile.value?.isAdmin ?? false;

  static String emailFor(String username) {
    final u = username.trim().toLowerCase();
    return u.contains('@') ? u : '$u@${Config.userEmailDomain}';
  }

  /// Columns clients may read (the device token is never exposed).
  static const profileColumns = 'id, username, full_name, role, active, business_name, '
      'business_description, created_at, last_seen_at, device_name, device_bound_at';

  /// Why the user was last signed out (shown on the login screen), if not by choice.
  static final ValueNotifier<String?> signOutReason = ValueNotifier(null);

  /// Password check, then claims the account for this phone.
  /// Fails if the account is already signed in on another phone.
  ///
  /// Returns true when the account has two-step verification: the caller must
  /// then ask for the authenticator code and call [completeSignIn].
  static Future<bool> signIn(String username, String password) async {
    signOutReason.value = null;
    try {
      await _sb.auth.signInWithPassword(email: emailFor(username), password: password);
    } on AuthException catch (e) {
      throw Exception(_friendly(e));
    }
    if (needsMfaCode) return true;
    await _finishSignIn();
    return false;
  }

  /// Second sign-in step: the 6-digit code from the authenticator app.
  static Future<void> completeSignIn(String code) async {
    await verifyMfaCode(code);
    await _finishSignIn();
  }

  static Future<void> _finishSignIn() async {
    try {
      await _claimDevice();
    } catch (e) {
      // Only end the session on THIS phone; the other phone stays signed in.
      await _localSignOut();
      rethrow;
    }
    await loadProfile();
  }

  // ------------------------------------------------- two-step verification

  /// Signed in with the password, but the account requires an authenticator code.
  static bool get needsMfaCode {
    final l = _sb.auth.mfa.getAuthenticatorAssuranceLevel();
    return l.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
        l.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  /// This session was verified with the authenticator (required for admin rights).
  static bool get isMfaVerified =>
      _sb.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
      AuthenticatorAssuranceLevels.aal2;

  static Future<void> verifyMfaCode(String code) async {
    final factors = await _sb.auth.mfa.listFactors();
    if (factors.totp.isEmpty) throw Exception('No authenticator is set up for this account.');
    try {
      await _sb.auth.mfa.challengeAndVerify(factorId: factors.totp.first.id, code: code.trim());
    } on AuthException catch (e) {
      throw Exception(e.message.toLowerCase().contains('invalid')
          ? 'Wrong or expired code. Try the newest code.'
          : e.message);
    }
  }

  /// Starts linking an authenticator app. Returns the otpauth:// link (shown
  /// as a QR code) and the secret for manual entry.
  static Future<({String factorId, String uri, String secret})> startMfaSetup() async {
    final factors = await _sb.auth.mfa.listFactors();
    for (final f in factors.all.where((f) => f.status == FactorStatus.unverified)) {
      await _sb.auth.mfa.unenroll(f.id); // abandoned earlier attempts
    }
    final r = await _sb.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'MobiWA',
      friendlyName: 'Authenticator ${DateTime.now().millisecondsSinceEpoch}',
    );
    final totp = r.totp!;
    return (factorId: r.id, uri: totp.uri, secret: totp.secret);
  }

  /// Confirms the authenticator with its first code; the session becomes aal2.
  static Future<void> finishMfaSetup(String factorId, String code) async {
    try {
      await _sb.auth.mfa.challengeAndVerify(factorId: factorId, code: code.trim());
    } on AuthException catch (e) {
      throw Exception(e.message.toLowerCase().contains('invalid')
          ? 'Wrong or expired code. Try the newest code.'
          : e.message);
    }
    Db.revision.value++;
  }

  static Future<void> _claimDevice() async {
    if (Device.id.isEmpty) throw Exception('Could not identify this phone.');
    final r = await _sb.rpc('claim_device',
        params: {'p_device_id': Device.id, 'p_device_name': Device.name}) as Map<String, dynamic>;
    if (r['ok'] == true) {
      await Device.setToken(r['token'] as String);
      return;
    }
    if (r['reason'] == 'disabled') throw Exception('Your account is disabled. Contact your admin.');
    final where = '${r['device_name'] ?? ''}'.trim();
    throw Exception(
      'This account is already signed in on ${where.isEmpty ? 'another phone' : where}. '
      'Sign out there first, or ask your admin to sign it out.',
    );
  }

  /// Loads the profile for the current session. Signs out disabled accounts.
  static Future<Profile> loadProfile() async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final row = await _sb.from('profiles').select(profileColumns).eq('id', user.id).single();
    final p = Profile.fromRow(row);
    if (!p.active) {
      await signOut(reason: 'Your account is disabled. Contact your admin.');
      throw Exception('Your account is disabled. Contact your admin.');
    }
    await Db.loadSystemCategories();
    profile.value = p;
    // Best effort "last seen" for the admin panel.
    _sb.from('profiles').update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', user.id).then((_) {}, onError: (_) {});
    return p;
  }

  /// True while this phone still holds the account. When the admin signed the
  /// user out (or the account was disabled), signs out here with a message.
  /// Network errors count as "still valid" so being offline never logs out.
  static Future<bool> verifyDevice() async {
    final p = profile.value;
    if (p == null) return false;
    if (p.isAdmin) return true;
    try {
      final ok = await _sb.rpc('device_ok');
      if (ok == true) return true;
      await signOut(
        release: false,
        reason: 'You were signed out. Your admin ended this session, or the account was '
            'disabled.',
      );
      return false;
    } catch (e) {
      debugPrint('MobiWA device check skipped: $e');
      return true;
    }
  }

  /// Signs out on this phone. [release] frees the account so it can be used on
  /// another phone (normal logout).
  static Future<void> signOut({bool release = true, String? reason}) async {
    if (release && Device.token != null) {
      try {
        await _sb.rpc('release_device');
      } catch (e) {
        debugPrint('MobiWA release failed: $e');
      }
    }
    signOutReason.value = reason;
    await _localSignOut();
  }

  /// Permanently deletes the signed-in user's account and all their data.
  static Future<void> deleteOwnAccount() async {
    try {
      await _sb.functions.invoke('admin-users', body: {'action': 'delete_self', 'confirm': 'DELETE'});
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(d is Map && d['error'] != null ? d['error'] : 'Could not delete the account.');
    }
    signOutReason.value = 'Your account and data were deleted.';
    await _localSignOut();
  }

  /// True while the app itself is signing out (vs. the server ending the session).
  static bool signingOut = false;

  static Future<void> _localSignOut() async {
    signingOut = true;
    try {
      await _sb.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
    } finally {
      signingOut = false;
    }
    await Device.setToken(null);
    profile.value = null;
    Db.reset();
  }

  /// App start with a saved session: make sure this phone still holds the
  /// account (claiming it if this phone has no token yet, e.g. after an
  /// update from a version without device lock), then load the profile.
  static Future<void> restoreSession() async {
    // App was closed between the password and the authenticator code.
    if (needsMfaCode) {
      signOutReason.value = 'Please sign in again.';
      await _localSignOut();
      return;
    }
    try {
      if (Device.token == null) await _claimDevice();
    } catch (e) {
      await signOut(release: false, reason: e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    try {
      await loadProfile();
    } catch (e) {
      if (profile.value == null) {
        signOutReason.value ??= e.toString().replaceFirst('Exception: ', '');
        await _localSignOut();
      }
      return;
    }
    await verifyDevice();
  }

  /// The signed-in user edits their own business info.
  static Future<void> updateBusiness({required String name, required String description}) async {
    final p = profile.value;
    if (p == null) return;
    await _sb
        .from('profiles')
        .update({'business_name': name.trim(), 'business_description': description.trim()})
        .eq('id', p.id);
    profile.value = Profile(
      id: p.id,
      username: p.username,
      fullName: p.fullName,
      role: p.role,
      active: p.active,
      businessName: name.trim(),
      businessDescription: description.trim(),
      createdAt: p.createdAt,
      lastSeenAt: p.lastSeenAt,
      deviceName: p.deviceName,
      deviceBoundAt: p.deviceBoundAt,
    );
  }

  static String _friendly(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'Wrong username or password.';
    }
    if (m.contains('banned')) return 'Your account is disabled. Contact your admin.';
    if (m.contains('network') || m.contains('socket') || m.contains('failed host lookup')) {
      return 'No internet connection.';
    }
    return e.message;
  }
}

/// Admin-only calls. The database refuses them for normal users.
class AdminApi {
  AdminApi._();

  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<List<UserStats>> userStats() async {
    final rows = await _sb.rpc('admin_user_stats') as List;
    return rows.cast<Map<String, dynamic>>().map(UserStats.fromRow).toList();
  }

  static Future<List<DayActivity>> dailyActivity({int days = 14}) async {
    final rows = await _sb.rpc('admin_daily_activity', params: {'days': days}) as List;
    return rows.cast<Map<String, dynamic>>().map(DayActivity.fromRow).toList();
  }

  static Future<Profile?> profileOf(String userId) async {
    final r = await _sb.from('profiles').select(Auth.profileColumns).eq('id', userId).maybeSingle();
    return r == null ? null : Profile.fromRow(r);
  }

  static Future<void> createUser({
    required String username,
    required String password,
    String fullName = '',
    Role role = Role.user,
    String businessName = '',
    String businessDescription = '',
  }) =>
      _call({
        'action': 'create',
        'username': username.trim().toLowerCase(),
        'password': password,
        'full_name': fullName,
        'role': role.name,
        'business_name': businessName,
        'business_description': businessDescription,
      });

  /// Only non-null fields are changed. An empty [password] keeps the old one.
  static Future<void> updateUser(
    String id, {
    String? username,
    String? password,
    String? fullName,
    Role? role,
    bool? active,
    String? businessName,
    String? businessDescription,
  }) =>
      _call({
        'action': 'update',
        'id': id,
        if (username != null) 'username': username.trim().toLowerCase(),
        if (password != null && password.isNotEmpty) 'password': password,
        if (fullName != null) 'full_name': fullName,
        if (role != null) 'role': role.name,
        if (active != null) 'active': active,
        if (businessName != null) 'business_name': businessName,
        if (businessDescription != null) 'business_description': businessDescription,
      });

  static Future<void> deleteUser(String id) => _call({'action': 'delete', 'id': id});

  /// Signs the user out of their phone and frees the account for another phone.
  static Future<void> forceLogout(String id) => _call({'action': 'logout', 'id': id});

  /// Messages from the website's contact form, newest first.
  static Future<List<ContactMessage>> contactMessages() async {
    final rows = await _sb
        .from('contact_messages')
        .select()
        .order('handled')
        .order('created_at', ascending: false)
        .limit(300);
    return rows.map(ContactMessage.fromRow).toList();
  }

  static Future<void> setMessageHandled(int id, bool handled) async {
    await _sb.from('contact_messages').update({'handled': handled}).eq('id', id);
    Db.revision.value++;
  }

  static Future<void> deleteMessage(int id) async {
    await _sb.from('contact_messages').delete().eq('id', id);
    Db.revision.value++;
  }

  static Future<void> _call(Map<String, Object> body) async {
    try {
      await _sb.functions.invoke('admin-users', body: body);
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(d is Map && d['error'] != null ? d['error'] : 'Request failed (${e.status})');
    }
    Db.revision.value++;
  }
}
