import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../data/auth.dart';
import '../../services/jobs.dart';
import '../../widgets/common.dart';
import '../../widgets/disclosures.dart';

/// Admin rights require two-step verification (enforced by the server). Shown
/// in the Admin tab until this session is verified with an authenticator code.
class MfaGate extends StatefulWidget {
  const MfaGate({super.key, required this.child});
  final Widget child;

  @override
  State<MfaGate> createState() => _MfaGateState();
}

class _MfaGateState extends State<MfaGate> {
  ({String factorId, String uri, String secret})? _setup;
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await Auth.startMfaSetup();
      if (mounted) setState(() => _setup = s);
    } catch (e) {
      if (mounted) setState(() => _error = Job.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final s = _setup;
    if (s == null || !RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'Enter the 6-digit code shown in the app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Auth.finishMfaSetup(s.factorId, _code.text);
      if (mounted) setState(() {}); // now verified → show the admin panel
    } catch (e) {
      if (mounted) setState(() => _error = Job.friendlyError(e));
      _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Auth.isMfaVerified) return widget.child;
    final cs = Theme.of(context).colorScheme;
    final s = _setup;

    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shield_outlined, size: 48, color: AppColors.brand),
                const SizedBox(height: 12),
                Text('Two-step verification',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'The admin panel can see every account, so it needs a second step besides your '
                  'password: a code from an authenticator app (Google Authenticator, Microsoft '
                  'Authenticator, 1Password…). After this, sign-in asks for the code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                  const SizedBox(height: 12),
                ],
                if (s == null)
                  FilledButton.icon(
                    onPressed: _busy ? null : _start,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: Text(_busy ? 'Preparing…' : 'Set up authenticator'),
                  )
                else ...[
                  const StepHeader(number: 1, title: 'Add MobiWA to your authenticator app'),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: QrImageView(data: s.uri, size: 200, backgroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Scan the QR code, or enter this key manually:',
                      textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: SelectableText(s.secret,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        tooltip: 'Copy key',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: s.secret));
                          showSnack(context, 'Key copied');
                        },
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => openLink(s.uri),
                    child: const Text('On this phone? Open in authenticator app'),
                  ),
                  const SizedBox(height: 16),
                  const StepHeader(number: 2, title: 'Enter the 6-digit code it shows'),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    style: const TextStyle(
                        fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                    onSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: Text(_busy ? 'Checking…' : 'Verify and continue'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Keep the authenticator safe. If you lose it, the second step can only be reset '
                    'from the Supabase dashboard (Authentication → Users → your account → MFA).',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
