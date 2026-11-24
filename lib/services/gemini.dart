import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';

/// The AI's decision for one number.
class AiDecision {
  final bool isCustomer;
  final String category;
  final String categoryDescription;
  final String name;
  final String reason;

  const AiDecision({
    required this.isCustomer,
    required this.category,
    required this.categoryDescription,
    required this.name,
    required this.reason,
  });
}

/// Raised for problems that stop the whole run (signed out, server not set up).
class AiFatalError implements Exception {
  final String message;
  AiFatalError(this.message);
  @override
  String toString() => message;
}

/// Calls the `ai-classify` Supabase Edge Function. The Gemini key is a
/// Supabase secret and never ships with the app.
class Gemini {
  Gemini._();

  static Future<AiDecision> classify({
    required String phone,
    required List<ChatMessage> messages,
    required List<ContactCategory> existing,
    required String business,
  }) async {
    final body = {
      'phone': phone,
      'business': business,
      'messages': [
        for (final m in messages) {'text': m.text, 'fromCustomer': m.fromCustomer, 'time': m.time},
      ],
      'categories': [
        for (final c in existing.where((c) => c.kind == CategoryKind.custom))
          {'name': c.name, 'description': c.description},
      ],
    };

    for (var attempt = 0;; attempt++) {
      try {
        final res = await Supabase.instance.client.functions
            .invoke('ai-classify', body: body)
            .timeout(const Duration(seconds: 90));
        final m = res.data as Map<String, dynamic>;
        return AiDecision(
          isCustomer: m['is_customer'] == true,
          category: '${m['category'] ?? ''}',
          categoryDescription: '${m['category_description'] ?? ''}',
          name: '${m['name'] ?? ''}',
          reason: '${m['reason'] ?? ''}',
        );
      } on FunctionException catch (e) {
        final msg = e.details is Map ? '${(e.details as Map)['error']}' : 'AI error (${e.status})';
        if (e.status == 401) throw AiFatalError('Your session expired. Please sign in again.');
        if (e.status == 403) throw AiFatalError(msg);
        if (e.status == 500 && msg.contains('GEMINI_API_KEY')) throw AiFatalError(msg);
        if ((e.status == 429 || e.status >= 500) && attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 8 * (attempt + 1)));
          continue;
        }
        if (e.status == 429) throw AiFatalError('AI limit reached. Try again later.');
        throw Exception(msg);
      } on TimeoutException {
        if (attempt < 1) continue;
        throw Exception('AI took too long');
      } on Exception catch (e) {
        // Network problems affect every number: stop instead of failing them all.
        if (attempt < 1) continue;
        throw AiFatalError('Connection problem: $e');
      }
    }
  }
}
