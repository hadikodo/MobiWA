import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Categories, contacts and activity, stored in Supabase.
///
/// Row-level security limits normal users to their own rows; admins can read
/// and change every user's rows. Listen to [revision] to refresh UI after writes.
class Db {
  Db._();

  static final ValueNotifier<int> revision = ValueNotifier(0);
  static void _changed() => revision.value++;

  static SupabaseClient get _sb => Supabase.instance.client;
  static String get _uid => _sb.auth.currentUser!.id;

  /// The signed-in user's Unnamed / Junk category ids (set by [loadSystemCategories]).
  static int unnamedId = -1;
  static int junkId = -1;

  /// PostgREST returns at most 1000 rows per request; page through bigger sets.
  static Future<List<Map<String, dynamic>>> _all(
      PostgrestTransformBuilder<List<Map<String, dynamic>>> Function() query) async {
    const page = 1000;
    final out = <Map<String, dynamic>>[];
    for (var from = 0;; from += page) {
      final rows = await query().range(from, from + page - 1);
      out.addAll(rows);
      if (rows.length < page) return out;
    }
  }

  static Future<void> loadSystemCategories() async {
    final rows = await _sb
        .from('categories')
        .select('id, kind')
        .eq('user_id', _uid)
        .inFilter('kind', ['unnamed', 'junk']);
    for (final r in rows) {
      if (r['kind'] == 'unnamed') unnamedId = (r['id'] as num).toInt();
      if (r['kind'] == 'junk') junkId = (r['id'] as num).toInt();
    }
  }

  static Future<int> _systemCategoryOf(String userId, String kind) async {
    if (userId == _uid) return kind == 'unnamed' ? unnamedId : junkId;
    final r = await _sb
        .from('categories')
        .select('id')
        .eq('user_id', userId)
        .eq('kind', kind)
        .single();
    return (r['id'] as num).toInt();
  }

  static void reset() {
    unnamedId = -1;
    junkId = -1;
    _changed();
  }

  // -------------------------------------------------------------- categories

  /// Categories of [userId] (default: signed-in user) with contact counts:
  /// Unnamed, then customer categories (largest first), then Junk.
  static Future<List<ContactCategory>> categories({String? userId}) async {
    final rows = await _sb
        .from('categories')
        .select('id, user_id, name, kind, description, contacts(count)')
        .eq('user_id', userId ?? _uid);
    final cats = rows.map(ContactCategory.fromRow).toList();
    int rank(ContactCategory c) => switch (c.kind) {
          CategoryKind.unnamed => 0,
          CategoryKind.custom => 1,
          CategoryKind.junk => 2,
        };
    cats.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final n = b.count.compareTo(a.count);
      return n != 0 ? n : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return cats;
  }

  static Future<ContactCategory?> category(int id) async {
    final r = await _sb
        .from('categories')
        .select('id, user_id, name, kind, description, contacts(count)')
        .eq('id', id)
        .maybeSingle();
    return r == null ? null : ContactCategory.fromRow(r);
  }

  /// Returns the existing category with this name (case-insensitive) or creates it.
  static Future<int> categoryIdFor(String name, {String description = '', String? userId}) async {
    final owner = userId ?? _uid;
    final clean = name.trim();
    final escaped = clean.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

    Future<Map<String, dynamic>?> find() => _sb
        .from('categories')
        .select('id, description')
        .eq('user_id', owner)
        .ilike('name', escaped)
        .maybeSingle();

    final existing = await find();
    if (existing != null) {
      final id = (existing['id'] as num).toInt();
      if (description.isNotEmpty && (existing['description'] as String).isEmpty) {
        await _sb.from('categories').update({'description': description}).eq('id', id);
      }
      return id;
    }
    try {
      final r = await _sb
          .from('categories')
          .insert({'user_id': owner, 'name': clean, 'kind': 'custom', 'description': description})
          .select('id')
          .single();
      _changed();
      return (r['id'] as num).toInt();
    } on PostgrestException catch (e) {
      // Created at the same moment elsewhere: use that one.
      if (e.code == '23505') {
        final again = await find();
        if (again != null) return (again['id'] as num).toInt();
      }
      rethrow;
    }
  }

  static Future<void> renameCategory(int id, String name) async {
    await _sb.from('categories').update({'name': name.trim()}).eq('id', id).eq('kind', 'custom');
    _changed();
  }

  /// Deletes a custom category; its numbers go back to the owner's Unnamed.
  static Future<void> deleteCategory(int id) async {
    final cat = await category(id);
    if (cat == null || cat.isSystem) return;
    final unnamed = await _systemCategoryOf(cat.userId, 'unnamed');
    await _sb
        .from('contacts')
        .update({'category_id': unnamed, 'ai_status': 'pending', 'ai_reason': ''})
        .eq('category_id', id);
    await _sb.from('categories').delete().eq('id', id);
    _changed();
  }

  // ---------------------------------------------------------------- contacts

  static Future<List<Contact>> contactsIn(int categoryId) async {
    final rows = await _all(() => _sb
        .from('contacts')
        .select()
        .eq('category_id', categoryId)
        .order('updated_at', ascending: false)
        .order('id'));
    return rows.map(Contact.fromRow).toList();
  }

  /// All of the signed-in user's contacts.
  static Future<List<Contact>> allContacts() async {
    final rows = await _all(() => _sb
        .from('contacts')
        .select()
        .eq('user_id', _uid)
        .order('updated_at', ascending: false)
        .order('id'));
    return rows.map(Contact.fromRow).toList();
  }

  static Future<int> count(int categoryId) =>
      _sb.from('contacts').count(CountOption.exact).eq('category_id', categoryId);

  /// Phones of every contact in the given categories (deduplicated).
  static Future<List<String>> phonesIn(Iterable<int> categoryIds) async {
    if (categoryIds.isEmpty) return [];
    final rows = await _all(() => _sb
        .from('contacts')
        .select('phone')
        .inFilter('category_id', categoryIds.toList())
        .order('id'));
    return rows.map((r) => r['phone'] as String).toSet().toList();
  }

  /// Adds new numbers to Unnamed. Numbers already in the app are left where
  /// they are. Returns how many were new.
  static Future<int> addUnnamed(List<String> phones, String sourceApp) async {
    var added = 0;
    for (var i = 0; i < phones.length; i += 500) {
      final chunk = phones.sublist(i, (i + 500).clamp(0, phones.length));
      final inserted = await _sb
          .from('contacts')
          .upsert(
            [
              for (final p in chunk)
                {'user_id': _uid, 'phone': p, 'category_id': unnamedId, 'source_app': sourceApp},
            ],
            onConflict: 'user_id,phone',
            ignoreDuplicates: true,
          )
          .select('id');
      added += inserted.length;
    }
    _changed();
    return added;
  }

  /// Adds saved phone contacts (with their names) for AI Sort and returns the
  /// MobiWA rows for all of them. New ones go to Unnamed; ones already in
  /// MobiWA keep their category (the AI re-checks them) and get the saved name
  /// if they had none.
  static Future<List<Contact>> importPhoneContacts(
    List<({String phone, String name})> items,
    String sourceApp,
  ) async {
    final byPhone = {for (final i in items) i.phone: i.name};
    final phones = byPhone.keys.toList();
    final out = <Contact>[];
    for (var i = 0; i < phones.length; i += 300) {
      final chunk = phones.sublist(i, (i + 300).clamp(0, phones.length));
      await _sb.from('contacts').upsert(
        [
          for (final p in chunk)
            {
              'user_id': _uid,
              'phone': p,
              'name': byPhone[p] ?? '',
              'category_id': unnamedId,
              'source_app': sourceApp,
            },
        ],
        onConflict: 'user_id,phone',
        ignoreDuplicates: true,
      );
      final rows = await _sb.from('contacts').select().eq('user_id', _uid).inFilter('phone', chunk);
      for (final r in rows) {
        var c = Contact.fromRow(r);
        final savedName = byPhone[c.phone] ?? '';
        if (c.name.isEmpty && savedName.isNotEmpty) {
          await _sb.from('contacts').update({'name': savedName}).eq('id', c.id);
          c = Contact.fromRow({...r, 'name': savedName});
        }
        out.add(c);
      }
    }
    _changed();
    return out;
  }

  static Future<void> saveAiResult({
    required int contactId,
    required int categoryId,
    required AiStatus status,
    String reason = '',
    String name = '',
  }) async {
    await _sb.from('contacts').update({
      'category_id': categoryId,
      'ai_status': status.name,
      'ai_reason': reason,
      if (name.isNotEmpty) 'name': name,
    }).eq('id', contactId);
    _changed();
  }

  /// Manual move by the user (or an admin).
  static Future<void> moveContacts(List<int> ids, int categoryId) async {
    if (ids.isEmpty) return;
    final target = await category(categoryId);
    final toUnnamed = target?.kind == CategoryKind.unnamed;
    await _sb.from('contacts').update({
      'category_id': categoryId,
      'ai_status': toUnnamed ? 'pending' : 'sorted',
      'ai_reason': toUnnamed ? '' : 'Moved manually',
    }).inFilter('id', ids);
    _changed();
  }

  static Future<void> renameContact(int id, String name) async {
    await _sb.from('contacts').update({'name': name.trim()}).eq('id', id);
    _changed();
  }

  static Future<void> deleteContacts(List<int> ids) async {
    if (ids.isEmpty) return;
    await _sb.from('contacts').delete().inFilter('id', ids);
    _changed();
  }

  /// Deletes all of the signed-in user's numbers and customer categories.
  static Future<void> clearAll() async {
    await _sb.from('contacts').delete().eq('user_id', _uid);
    await _sb.from('categories').delete().eq('user_id', _uid).eq('kind', 'custom');
    _changed();
  }

  // ---------------------------------------------------------------- activity

  /// Records a finished action for the admin analytics. Never throws.
  static Future<void> logActivity(String kind, Map<String, Object> stats) async {
    try {
      await _sb.from('activity').insert({'user_id': _uid, 'kind': kind, 'stats': stats});
    } catch (e) {
      debugPrint('activity log failed: $e');
    }
  }
}
