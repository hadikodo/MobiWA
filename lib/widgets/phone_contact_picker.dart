import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../services/jobs.dart';
import '../services/native.dart';
import 'common.dart';
import 'disclosures.dart';

/// Opens a bottom sheet to choose saved phone contacts (filter: on WhatsApp /
/// all, search, select all). Asks for the Contacts permission when needed.
/// Returns the chosen contacts, or null if cancelled.
Future<List<PhoneContact>?> pickPhoneContacts(
  BuildContext context, {
  Set<String> initial = const {},
  String confirmLabel = 'Done',
}) =>
    showModalBottomSheet<List<PhoneContact>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PhoneContactPicker(initial: initial, confirmLabel: confirmLabel),
    );

enum _Filter { whatsapp, all }

class _PhoneContactPicker extends StatefulWidget {
  const _PhoneContactPicker({required this.initial, required this.confirmLabel});
  final Set<String> initial;
  final String confirmLabel;

  @override
  State<_PhoneContactPicker> createState() => _PhoneContactPickerState();
}

class _PhoneContactPickerState extends State<_PhoneContactPicker> {
  List<PhoneContact>? _all;
  String? _permission; // null = checking, "granted" | "denied" | "blocked"
  String? _error;
  late final Set<String> _sel = {...widget.initial};
  _Filter _filter = _Filter.whatsapp;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _permission = null;
      _error = null;
    });
    try {
      // Google Play prominent disclosure before the system permission dialog.
      if (!await Disclosures.contacts(context)) {
        if (mounted) setState(() => _permission = 'denied');
        return;
      }
      final p = await Native.requestContactsPermission();
      if (!mounted) return;
      setState(() => _permission = p);
      if (p != 'granted') return;
      final list = await Native.phoneContacts();
      if (!mounted) return;
      setState(() {
        _all = list;
        if (!list.any((c) => c.onWhatsApp)) _filter = _Filter.all;
      });
    } catch (e) {
      if (mounted) setState(() => _error = Job.friendlyError(e));
    }
  }

  List<PhoneContact> get _visible {
    final q = _q.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    return (_all ?? const <PhoneContact>[])
        .where((c) => _filter == _Filter.all || c.onWhatsApp)
        .where((c) =>
            q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            (qDigits.isNotEmpty && c.phone.replaceAll(RegExp(r'\D'), '').contains(qDigits)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.88;
    return SizedBox(height: height, child: _body(context));
  }

  Widget _body(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not read contacts',
        message: _error,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (_permission == 'denied' || _permission == 'blocked') {
      final blocked = _permission == 'blocked';
      return EmptyState(
        icon: Icons.contacts_outlined,
        title: 'Allow access to contacts',
        message: blocked
            ? 'Contacts access is turned off for MobiWA. Open App info → Permissions → '
                'Contacts → Allow, then come back.'
            : 'MobiWA needs your permission to show your saved contacts. '
                'They are only read on this phone.',
        action: FilledButton(
          onPressed: blocked ? Native.openAppSettings : _load,
          child: Text(blocked ? 'Open App info' : 'Allow'),
        ),
      );
    }
    final all = _all;
    if (all == null) return const Center(child: CircularProgressIndicator());
    if (all.isEmpty) {
      return const EmptyState(
          icon: Icons.person_off_outlined, title: 'No saved contacts with phone numbers');
    }

    final visible = _visible;
    final waCount = all.where((c) => c.onWhatsApp).length;
    final allVisibleSelected = visible.isNotEmpty && visible.every((c) => _sel.contains(c.phone));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Phone contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_Filter>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _Filter.whatsapp,
                      icon: const Icon(Icons.chat_rounded, size: 18),
                      label: Text('On WhatsApp · $waCount'),
                    ),
                    ButtonSegment(
                      value: _Filter.all,
                      icon: const Icon(Icons.contacts_rounded, size: 18),
                      label: Text('All · ${all.length}'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search name or number',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: allVisibleSelected,
                onChanged: visible.isEmpty
                    ? null
                    : (v) => setState(() {
                          for (final c in visible) {
                            v == true ? _sel.add(c.phone) : _sel.remove(c.phone);
                          }
                        }),
                title: Text('Select all ${visible.length} shown',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'No matches')
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final c = visible[i];
                    final on = _sel.contains(c.phone);
                    return CheckboxListTile(
                      value: on,
                      onChanged: (v) => setState(() => v == true ? _sel.add(c.phone) : _sel.remove(c.phone)),
                      secondary: CircleAvatar(
                        backgroundColor: AppColors.brand.withValues(alpha: 0.12),
                        foregroundColor: AppColors.brand,
                        child: Text(c.label.characters.first.toUpperCase()),
                      ),
                      title: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Row(children: [
                        Flexible(child: Text(c.phone, overflow: TextOverflow.ellipsis)),
                        if (c.onWhatsApp) ...[
                          const SizedBox(width: 6),
                          Icon(c.business ? Icons.storefront_rounded : Icons.chat_rounded,
                              size: 14, color: AppColors.brand),
                        ],
                      ]),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                all.where((c) => _sel.contains(c.phone)).toList(),
              ),
              child: Text('${widget.confirmLabel} · ${_sel.length} selected'),
            ),
          ),
        ),
      ],
    );
  }
}
