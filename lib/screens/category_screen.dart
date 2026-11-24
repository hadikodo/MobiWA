import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/auth.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../services/native.dart';
import '../widgets/common.dart';
import 'ai_sort_screen.dart';
import 'contacts_screen.dart';
import 'send_screen.dart';

/// Numbers inside one category. Tap a number for actions; long-press to select many.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.categoryId});
  final int categoryId;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final Set<int> _selected = {};
  String _query = '';

  bool get _selecting => _selected.isNotEmpty;

  /// Loads the category and its owner's other categories (an admin may be
  /// looking at another user's category).
  Future<({ContactCategory? cat, List<Contact> contacts, List<ContactCategory> all})> _load() async {
    final cat = await Db.category(widget.categoryId);
    if (cat == null) return (cat: null, contacts: <Contact>[], all: <ContactCategory>[]);
    final results = await Future.wait([
      Db.contactsIn(widget.categoryId),
      Db.categories(userId: cat.userId),
    ]);
    return (
      cat: cat,
      contacts: results[0] as List<Contact>,
      all: results[1] as List<ContactCategory>,
    );
  }

  Future<int?> _chooseCategory(List<ContactCategory> all) => showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Move to', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                for (final cat in all.where((x) => x.id != widget.categoryId))
                  ListTile(
                    leading: Icon(categoryLook(cat).icon, color: categoryLook(cat).color),
                    title: Text(cat.name),
                    trailing: Text('${cat.count}'),
                    onTap: () => Navigator.pop(c, cat.id),
                  ),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('New category…'),
                  onTap: () async {
                    final name = await askText(c, title: 'New category', hint: 'e.g. Car Parts');
                    if (name == null || name.isEmpty) return;
                    final owner = all.firstOrNull?.userId;
                    final id = await Db.categoryIdFor(name, userId: owner);
                    if (c.mounted) Navigator.pop(c, id);
                  },
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _move(List<int> ids, List<ContactCategory> all) async {
    final target = await _chooseCategory(all);
    if (target == null) return;
    await Db.moveContacts(ids, target);
    setState(_selected.clear);
    if (mounted) showSnack(context, 'Moved ${ids.length}');
  }

  Future<void> _delete(List<int> ids) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${ids.length} ${ids.length == 1 ? 'number' : 'numbers'}?'),
        content: const Text('They are removed from MobiWA only. WhatsApp is not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Db.deleteContacts(ids);
    setState(_selected.clear);
  }

  void _contactActions(Contact c, List<ContactCategory> all) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(c.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (c.name.isNotEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(c.phone)),
            if (c.aiReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(children: [
                  const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.ai),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.aiReason)),
                ]),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Open in WhatsApp'),
              onTap: () {
                Navigator.pop(s);
                Native.openChat(c.phone, app: WaApp.fromPackage(c.sourceApp));
              },
            ),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Send a message'),
              onTap: () {
                Navigator.pop(s);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SendScreen(initialPhones: {c.phone})));
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Move to another category'),
              onTap: () {
                Navigator.pop(s);
                _move([c.id], all);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit name'),
              onTap: () async {
                Navigator.pop(s);
                final n = await askText(context, title: 'Name', initial: c.name, hint: 'Customer name');
                if (n != null) await Db.renameContact(c.id, n);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(s);
                _delete([c.id]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _categoryMenu(String action, ContactCategory cat) async {
    switch (action) {
      case 'rename':
        final n = await askText(context, title: 'Rename category', initial: cat.name);
        if (n != null && n.isNotEmpty) await Db.renameCategory(cat.id, n);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Delete "${cat.name}"?'),
            content: Text(cat.count == 0
                ? 'This category is empty.'
                : 'Its ${cat.count} numbers go back to Unnamed.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await Db.deleteCategory(cat.id);
          if (mounted) Navigator.of(context).pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch(
      listenables: [Db.revision],
      builder: (context) => FutureBuilder(
        future: _load(),
        builder: (context, snap) {
          final data = snap.data;
          final cat = data?.cat;
          if (data == null) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (cat == null) return const Scaffold(body: SizedBox.shrink());
          final q = _query.toLowerCase();
          final contacts = data.contacts
              .where((c) => q.isEmpty || c.phone.contains(q) || c.name.toLowerCase().contains(q))
              .toList();
          final look = categoryLook(cat);
          final isMine = cat.userId == Auth.profile.value?.id;

          return PopScope(
            canPop: !_selecting,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(_selected.clear);
            },
            child: Scaffold(
              appBar: _selecting
                  ? AppBar(
                      leading: IconButton(
                          onPressed: () => setState(_selected.clear), icon: const Icon(Icons.close)),
                      title: Text('${_selected.length} selected'),
                      actions: [
                        IconButton(
                          tooltip: 'Select all',
                          onPressed: () => setState(() => _selected.addAll(contacts.map((c) => c.id))),
                          icon: const Icon(Icons.select_all_rounded),
                        ),
                        IconButton(
                          tooltip: 'Send',
                          onPressed: () {
                            final phones = data.contacts
                                .where((c) => _selected.contains(c.id))
                                .map((c) => c.phone)
                                .toSet();
                            setState(_selected.clear);
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => SendScreen(initialPhones: phones)));
                          },
                          icon: const Icon(Icons.send_outlined),
                        ),
                        IconButton(
                          tooltip: 'Move',
                          onPressed: () => _move(_selected.toList(), data.all),
                          icon: const Icon(Icons.drive_file_move_outline),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () => _delete(_selected.toList()),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    )
                  : AppBar(
                      title: Text(cat.name),
                      actions: [
                        if (!cat.isSystem)
                          PopupMenuButton<String>(
                            onSelected: (a) => _categoryMenu(a, cat),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'rename', child: Text('Rename')),
                              PopupMenuItem(value: 'delete', child: Text('Delete category')),
                            ],
                          ),
                      ],
                    ),
              floatingActionButton: _selecting || cat.count == 0
                  ? null
                  : cat.kind == CategoryKind.unnamed && !isMine
                      ? null
                  : cat.kind == CategoryKind.unnamed
                      ? FloatingActionButton.extended(
                          backgroundColor: AppColors.ai,
                          foregroundColor: Colors.white,
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const AiSortScreen())),
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('AI Sort'),
                        )
                      : FloatingActionButton.extended(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SendScreen(initialCategoryIds: {cat.id}))),
                          icon: const Icon(Icons.send_rounded),
                          label: Text('Send to all ${cat.count}'),
                        ),
              body: cat.count == 0
                  ? EmptyState(
                      icon: look.icon,
                      title: 'No numbers here yet',
                      message: switch (cat.kind) {
                        CategoryKind.unnamed => 'Use "Get Numbers" on the Home screen to collect '
                            'unsaved numbers from WhatsApp.',
                        CategoryKind.junk => 'Numbers the AI decides are not customers land here.',
                        CategoryKind.custom => 'AI Sort puts matching customers here. '
                            'You can also move numbers here yourself.',
                      },
                    )
                  : Column(
                      children: [
                        if (cat.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Text(cat.description,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText: 'Search ${cat.count} numbers',
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                            itemCount: contacts.length,
                            itemBuilder: (_, i) {
                              final c = contacts[i];
                              final sel = _selected.contains(c.id);
                              return ListTile(
                                selected: sel,
                                leading: CircleAvatar(
                                  backgroundColor: look.color.withValues(alpha: 0.15),
                                  foregroundColor: look.color,
                                  child: sel
                                      ? const Icon(Icons.check_rounded)
                                      : Text(c.name.isNotEmpty
                                          ? c.name.characters.first.toUpperCase()
                                          : '#'),
                                ),
                                title: Text(c.label,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  [
                                    if (c.name.isNotEmpty) c.phone,
                                    if (c.aiReason.isNotEmpty) c.aiReason,
                                    if (c.aiReason.isEmpty && cat.kind == CategoryKind.unnamed)
                                      'Not sorted yet',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  if (_selecting) {
                                    setState(() => sel ? _selected.remove(c.id) : _selected.add(c.id));
                                  } else {
                                    _contactActions(c, data.all);
                                  }
                                },
                                onLongPress: () => setState(() => _selected.add(c.id)),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
