import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/auth.dart';
import '../services/jobs.dart';
import '../widgets/disclosures.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});

  /// Shown above the form, e.g. "Your account is disabled".
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  bool _needCode = false; // password OK, authenticator code required
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_needCode) {
        await Auth.completeSignIn(_code.text);
      } else if (await Auth.signIn(_user.text, _pass.text)) {
        if (mounted) setState(() => _needCode = true);
      }
      // When fully signed in, AuthGate switches to the app.
    } catch (e) {
      if (mounted) {
        setState(() => _error = Job.friendlyError(e));
        _code.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelCode() async {
    await Auth.signOut(release: false);
    if (mounted) {
      setState(() {
        _needCode = false;
        _code.clear();
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset('assets/images/logo.png', width: 80, height: 80),
                      ),
                      const SizedBox(height: 20),
                      Text('Welcome to MobiWA',
                          textAlign: TextAlign.center,
                          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('Sign in with the username and password you received from MobiWA.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 32),
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_error!)),
                          ]),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_needCode) ...[
                        // Step 2: two-step verification.
                        const Icon(Icons.verified_user_outlined, size: 32, color: AppColors.brand),
                        const SizedBox(height: 8),
                        const Text('Enter the 6-digit code from your authenticator app.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _code,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())
                              ? null
                              : 'Enter the 6 digits',
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _user,
                          autofillHints: const [AutofillHints.username],
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your username' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _pass,
                          obscureText: _hide,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _hide = !_hide),
                              icon: Icon(_hide
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                          validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : Text(_needCode ? 'Verify' : 'Sign in'),
                      ),
                      if (_needCode)
                        TextButton(
                          onPressed: _busy ? null : _cancelCode,
                          child: const Text('Back'),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'By signing in you agree to our',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => openLink(Config.termsUrl),
                            child: const Text('Terms of Service'),
                          ),
                          Text('·', style: TextStyle(color: cs.onSurfaceVariant)),
                          TextButton(
                            onPressed: () => openLink(Config.privacyUrl),
                            child: const Text('Privacy Policy'),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => openLink('mailto:${Config.supportEmail}'),
                        child: const Text('Need an account? ${Config.supportEmail}',
                            style: TextStyle(fontSize: 12)),
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
}
