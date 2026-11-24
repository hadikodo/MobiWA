import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../data/models.dart';
import '../../services/jobs.dart';
import '../../widgets/common.dart';

/// Add a user (when [existing] is null) or edit one. Returns true when saved.
Future<bool?> showUserForm(BuildContext context, {Profile? existing}) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _UserForm(existing: existing),
      ),
    );

class _UserForm extends StatefulWidget {
  const _UserForm({this.existing});
  final Profile? existing;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.existing?.username ?? '');
  late final _fullName = TextEditingController(text: widget.existing?.fullName ?? '');
  final _password = TextEditingController();
  late final _bizName = TextEditingController(text: widget.existing?.businessName ?? '');
  late final _bizDesc = TextEditingController(text: widget.existing?.businessDescription ?? '');
  late Role _role = widget.existing?.role ?? Role.user;
  bool _hide = true;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;
  bool get _isSelf => widget.existing?.id == Auth.profile.value?.id;

  @override
  void dispose() {
    for (final c in [_username, _fullName, _password, _bizName, _bizDesc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final e = widget.existing;
      if (e == null) {
        await AdminApi.createUser(
          username: _username.text,
          password: _password.text,
          fullName: _fullName.text.trim(),
          role: _role,
          businessName: _bizName.text.trim(),
          businessDescription: _bizDesc.text.trim(),
        );
      } else {
        final newUsername = _username.text.trim().toLowerCase();
        await AdminApi.updateUser(
          e.id,
          username: newUsername != e.username ? newUsername : null,
          password: _password.text,
          fullName: _fullName.text.trim(),
          role: _isSelf ? null : _role,
          businessName: _bizName.text.trim(),
          businessDescription: _bizDesc.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = Job.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Edit user' : 'Add user',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: cs.error)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _username,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  helperText: 'Used to sign in. Letters, numbers, dot, dash, underscore.',
                ),
                validator: (v) {
                  final s = (v ?? '').trim().toLowerCase();
                  if (!RegExp(r'^[a-z0-9._@-]{3,64}$').hasMatch(s)) {
                    return '3-64 characters: letters, numbers, . _ -';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _hide,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: _isEdit ? 'New password' : 'Password',
                  helperText: _isEdit
                      ? 'Leave empty to keep the current password'
                      : '10+ characters, letters and numbers',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _hide = !_hide),
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: (v) {
                  final s = v ?? '';
                  if (_isEdit && s.isEmpty) return null;
                  if (s.length < 10) return 'At least 10 characters';
                  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
                    return 'Use letters and numbers';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name (optional)'),
              ),
              const SizedBox(height: 16),
              const Text('Role', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SegmentedButton<Role>(
                segments: const [
                  ButtonSegment(
                      value: Role.user,
                      icon: Icon(Icons.person_outline_rounded),
                      label: Text('User')),
                  ButtonSegment(
                      value: Role.admin,
                      icon: Icon(Icons.admin_panel_settings_outlined),
                      label: Text('Admin')),
                ],
                selected: {_role},
                onSelectionChanged: _isSelf ? null : (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 4),
              Text(
                _isSelf
                    ? 'You can\'t change your own role.'
                    : _role == Role.admin
                        ? 'Admins can see and manage every user and their numbers.'
                        : 'Users only see their own numbers.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SectionTitle('Business'),
              TextFormField(
                controller: _bizName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Business name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bizDesc,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What do they sell?',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create user')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
