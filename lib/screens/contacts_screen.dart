import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../widgets/common.dart';
import 'category_screen.dart';

/// All categories: Unnamed first, customer categories, Junk last.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  Future<void> _addCategory(BuildContext context) async {
    final name = await askText(context, title: 'New category', hint: 'e.g. Car Parts');
    if (name == null || name.isEmpty) return;
    await Db.categoryIdFor(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            tooltip: 'New category',
            onPressed: () => _addCategory(context),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: Watch(
        listenables: [Db.revision],
        builder: (context) => FutureBuilder<List<ContactCategory>>(
          future: Db.categories(),
          builder: (context, snap) {
            final cats = snap.data;
            if (cats == null) return const Center(child: CircularProgressIndicator());
            final unnamed = cats.where((c) => c.kind == CategoryKind.unnamed);
            final custom = cats.where((c) => c.kind == CategoryKind.custom).toList();
            final junk = cats.where((c) => c.kind == CategoryKind.junk);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                for (final c in unnamed) _CategoryTile(c, subtitle: 'Waiting for AI Sort'),
                SectionTitle('Customers · ${custom.fold<int>(0, (s, c) => s + c.count)}'),
                if (custom.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No customer categories yet. Run AI Sort and they will be created '
                        'automatically, or tap the folder icon above to add one.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  for (final c in custom)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CategoryTile(c),
                    ),
                const SectionTitle('Other'),
                for (final c in junk) _CategoryTile(c, subtitle: 'Not customers'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(this.c, {this.subtitle});
  final ContactCategory c;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final look = categoryLook(c);
    final sub = subtitle ?? (c.description.isNotEmpty ? c.description : null);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: IconTile(look.icon, look.color, size: 44),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: sub == null ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${c.count}',
                style: TextStyle(fontWeight: FontWeight.w700, color: look.color, fontSize: 16)),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => CategoryScreen(categoryId: c.id))),
      ),
    );
  }
}

/// Simple one-field dialog. Returns the trimmed text, or null if cancelled.
Future<String?> askText(BuildContext context,
    {required String title, String hint = '', String initial = '', String action = 'Save'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(action)),
      ],
    ),
  );
}
