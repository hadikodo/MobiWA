import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/phone.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../services/app_status.dart';
import '../services/jobs.dart';
import '../services/native.dart';
import '../widgets/disclosures.dart';
import '../widgets/common.dart';
import '../widgets/phone_contact_picker.dart';
import 'send_progress_screen.dart';

/// Step 3: pick recipients (categories + typed numbers + individual contacts),
/// write the message (text / image / video / PDF, with caption), then send.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.initialCategoryIds = const {}, this.initialPhones = const {}});

  final Set<int> initialCategoryIds;
  final Set<String> initialPhones;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  List<ContactCategory> _categories = [];
  late final Set<int> _categoryIds = {...widget.initialCategoryIds};
  late final Set<String> _picked = {...widget.initialPhones};
  final _typed = TextEditingController();
  final _text = TextEditingController();
  String _countryCode = '';
  List<String> _categoryPhones = [];

  MessageType _type = MessageType.text;
  PickedMedia? _media;
  WaApp? _app;

  @override
  void initState() {
    super.initState();
    _load();
    _typed.addListener(() => setState(() {}));
    _text.addListener(() => setState(() {}));
  }

  Future<void> _load() async {
    final cc = await Settings.countryCode();
    final last = await Settings.lastApp();
    final installed = AppStatus.instance.apps;
    if (!mounted) return;
    setState(() {
      _countryCode = cc;
      _app = (last != null && installed.contains(last))
          ? last
          : (installed.isNotEmpty ? installed.first : null);
    });
    try {
      final cats = await Db.categories();
      if (mounted) setState(() => _categories = cats);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not load categories: ${Job.friendlyError(e)}');
    }
    await _refreshCategoryPhones();
  }

  Future<void> _refreshCategoryPhones() async {
    try {
      final phones = await Db.phonesIn(_categoryIds);
      if (mounted) setState(() => _categoryPhones = phones);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not load numbers: ${Job.friendlyError(e)}');
    }
  }

  @override
  void dispose() {
    _typed.dispose();
    _text.dispose();
    super.dispose();
  }

  ({List<String> valid, List<String> invalid}) get _typedParsed =>
      Phone.parseList(_typed.text, defaultCountryCode: _countryCode);

  /// Contacts picked from the phone's address book (not imported into MobiWA).
  List<PhoneContact> _phonePicked = [];

  ({List<String> valid, int invalid}) get _phoneParsed {
    final valid = <String>[];
    var invalid = 0;
    for (final c in _phonePicked) {
      final n = Phone.normalize(c.phone, defaultCountryCode: _countryCode);
      if (n == null) {
        invalid++;
      } else {
        valid.add(n);
      }
    }
    return (valid: valid, invalid: invalid);
  }

  List<String> get _recipients =>
      {..._categoryPhones, ..._picked, ..._phoneParsed.valid, ..._typedParsed.valid}.toList();

  Future<void> _pickPhoneContacts() async {
    final r = await pickPhoneContacts(context, initial: _phonePicked.map((c) => c.phone).toSet());
    if (r != null) setState(() => _phonePicked = r);
  }

  String? get _problem {
    if (_recipients.isEmpty) return 'Choose who gets the message';
    if (_type == MessageType.text && _text.text.trim().isEmpty) return 'Write your message';
    if (_type.hasMedia && _media == null) return 'Attach a ${_type.label.toLowerCase()}';
    if (_app == null) return 'Choose a WhatsApp';
    return null;
  }

  Future<void> _pickContacts() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ContactPicker(initial: _picked, categories: _categories),
    );
    if (result != null) {
      setState(() => _picked
        ..clear()
        ..addAll(result));
    }
  }

  Future<void> _attach() async {
    try {
      final m = await Native.pickMedia(_type);
      if (m != null) setState(() => _media = m);
    } catch (e) {
      if (mounted) showSnack(context, Job.friendlyError(e));
    }
  }

  Future<void> _send() async {
    final problem = _problem;
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    if (!await AppStatus.instance.ensureAutomation()) {
      if (mounted) showSnack(context, automationOffMessage());
      if (mounted) await openAutomationSettings(context);
      return;
    }
    if (!mounted) return;
    if (Job.active != null) {
      showSnack(context, 'Please wait: ${Job.active!.title.toLowerCase()} is still running.');
      return;
    }
    // Re-read category members now, in case a chip was toggled a moment ago.
    try {
      _categoryPhones = await Db.phonesIn(_categoryIds);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not load numbers: ${Job.friendlyError(e)}');
      return;
    }
    if (!mounted) return;
    final recipients = _recipients;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.send_rounded, color: AppColors.send),
        title:
            Text('Send to ${recipients.length} ${recipients.length == 1 ? 'number' : 'numbers'}?'),
        content: Text(
          'MobiWA will open ${_app!.label}, send your ${_type.label.toLowerCase()} message to each '
          'number one by one, and close the chat.\n\n'
          'Keep the phone unlocked and don\'t touch it. You can tap STOP on the screen any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start sending')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final text = _text.text.trim();
    // Start without awaiting: the progress screen follows the job.
    Job.send.start(
      app: _app!,
      recipients: recipients,
      text: text,
      media: _type.hasMedia ? _media : null,
    );
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const SendProgressScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typed = _typedParsed;
    final total = _recipients.length;
    final problem = _problem;

    return Scaffold(
      appBar: AppBar(title: const Text('Send Messages')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---------------------------------------------------- WHO
                  const StepHeader(
                    number: 1,
                    title: 'Who gets it?',
                    subtitle: 'Mix categories, contacts and typed numbers. Duplicates are removed.',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Categories', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (_categories.every((c) => c.count == 0))
                            Text('No numbers yet. Use Get Numbers first, or type numbers below.',
                                style: TextStyle(color: cs.onSurfaceVariant))
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final c in _categories.where((c) => c.count > 0))
                                  FilterChip(
                                    avatar: Icon(categoryLook(c).icon,
                                        size: 18, color: categoryLook(c).color),
                                    label: Text('${c.name} · ${c.count}'),
                                    selected: _categoryIds.contains(c.id),
                                    onSelected: (v) {
                                      setState(() =>
                                          v ? _categoryIds.add(c.id) : _categoryIds.remove(c.id));
                                      _refreshCategoryPhones();
                                    },
                                  ),
                              ],
                            ),
                          const Divider(height: 28),
                          Row(
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('MobiWA contacts',
                                        style: TextStyle(fontWeight: FontWeight.w700)),
                                    Text('Numbers already in your categories',
                                        style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _pickContacts,
                                icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                                label:
                                    Text(_picked.isEmpty ? 'Choose' : '${_picked.length} chosen'),
                              ),
                            ],
                          ),
                          // Phone address book: Android only (browsers can't read it).
                          if (!kIsWeb) ...[
                            const Divider(height: 20),
                            Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Phone contacts',
                                          style: TextStyle(fontWeight: FontWeight.w700)),
                                      Text('Saved on your phone or WhatsApp',
                                          style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _pickPhoneContacts,
                                  icon: const Icon(Icons.contacts_rounded, size: 18),
                                  label: Text(_phonePicked.isEmpty
                                      ? 'Choose'
                                      : '${_phonePicked.length} chosen'),
                                ),
                              ],
                            ),
                            if (_phoneParsed.invalid > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${_phoneParsed.invalid} chosen contacts have no country code and will be '
                                  'skipped. Set your country code in Settings.',
                                  style: TextStyle(fontSize: 12, color: cs.error),
                                ),
                              ),
                          ],
                          const Divider(height: 20),
                          const Text('Type or paste numbers',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _typed,
                            keyboardType: TextInputType.multiline,
                            minLines: 2,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText: _countryCode.isEmpty
                                  ? 'One per line, with country code\n+961 70 123 456'
                                  : 'One per line\n70 123 456',
                            ),
                          ),
                          if (_typed.text.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${typed.valid.length} valid'
                                '${typed.invalid.isEmpty ? '' : ' · ${typed.invalid.length} not valid: ${typed.invalid.take(3).join(', ')}'}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: typed.invalid.isEmpty ? cs.onSurfaceVariant : cs.error),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // --------------------------------------------------- WHAT
                  const StepHeader(number: 2, title: 'What do you want to send?'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<MessageType>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: MessageType.text,
                            icon: Icon(Icons.notes_rounded),
                            label: Text('Text')),
                        ButtonSegment(
                            value: MessageType.image,
                            icon: Icon(Icons.image_outlined),
                            label: Text('Image')),
                        ButtonSegment(
                            value: MessageType.video,
                            icon: Icon(Icons.videocam_outlined),
                            label: Text('Video')),
                        ButtonSegment(
                            value: MessageType.pdf,
                            icon: Icon(Icons.picture_as_pdf_outlined),
                            label: Text('PDF')),
                      ],
                      selected: {_type},
                      onSelectionChanged: (s) => setState(() {
                        if (s.first != _type) _media = null;
                        _type = s.first;
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_type.hasMedia) ...[
                    _AttachmentBox(
                        type: _type,
                        media: _media,
                        onPick: _attach,
                        onRemove: () => setState(() => _media = null)),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _text,
                    minLines: 3,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: _type.hasMedia ? 'Caption (optional)' : 'Message',
                      alignLabelWithHint: true,
                      hintText: 'Hello! We have new offers this week…',
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ---------------------------------------------------- APP
                  const StepHeader(number: 3, title: 'Send from'),
                  WaAppPicker(selected: _app, onChanged: (a) => setState(() => _app = a)),
                ],
              ),
            ),

            // ----------------------------------------------------- footer
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_alt_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text('$total ${total == 1 ? 'recipient' : 'recipients'}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (problem != null)
                        Flexible(
                          child: Text(problem,
                              textAlign: TextAlign.end,
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: problem == null ? _send : null,
                      icon: const Icon(Icons.send_rounded),
                      label: Text(total == 0 ? 'Send' : 'Send to $total'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentBox extends StatelessWidget {
  const _AttachmentBox(
      {required this.type, required this.media, required this.onPick, required this.onRemove});
  final MessageType type;
  final PickedMedia? media;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  IconData get _icon => switch (type) {
        MessageType.image => Icons.image_rounded,
        MessageType.video => Icons.movie_rounded,
        MessageType.pdf => Icons.picture_as_pdf_rounded,
        MessageType.text => Icons.notes_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = media;
    if (m == null) {
      return Material(
        color: AppColors.brand.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.brand.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPick,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Column(
              children: [
                const Icon(Icons.add_circle_outline_rounded, color: AppColors.brand, size: 34),
                const SizedBox(height: 8),
                Text(
                    'Choose ${type == MessageType.image ? 'an image' : type == MessageType.video ? 'a video' : 'a PDF'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.brand)),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: IconTile(_icon, AppColors.brand, size: 44),
        title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(m.sizeLabel, style: TextStyle(color: cs.onSurfaceVariant)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: onPick, icon: const Icon(Icons.swap_horiz_rounded), tooltip: 'Replace'),
            IconButton(
                onPressed: onRemove, icon: const Icon(Icons.close_rounded), tooltip: 'Remove'),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to choose individual saved numbers.
class _ContactPicker extends StatefulWidget {
  const _ContactPicker({required this.initial, required this.categories});
  final Set<String> initial;
  final List<ContactCategory> categories;

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  late final Set<String> _sel = {...widget.initial};
  List<Contact> _all = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    Db.allContacts().then(
      (v) => mounted ? setState(() => _all = v) : null,
      onError: (Object e) => debugPrint('MobiWA contacts load failed: $e'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final c in widget.categories) c.id: c.name};
    final q = _q.toLowerCase();
    final list = _all
        .where((c) =>
            q.isEmpty ||
            c.phone.contains(q) ||
            c.name.toLowerCase().contains(q) ||
            (names[c.categoryId] ?? '').toLowerCase().contains(q))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search number, name or category',
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(icon: Icons.person_off_outlined, title: 'No contacts')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return CheckboxListTile(
                        value: _sel.contains(c.phone),
                        onChanged: (v) =>
                            setState(() => v == true ? _sel.add(c.phone) : _sel.remove(c.phone)),
                        title: Text(c.label),
                        subtitle: Text(
                            '${c.name.isNotEmpty ? '${c.phone} · ' : ''}${names[c.categoryId] ?? ''}'),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _sel),
                child: Text('Done · ${_sel.length} chosen'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
