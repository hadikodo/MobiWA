// lib/services/gemini_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import '../models/lead.dart';
import '../models/lead_message.dart';

class GeminiAnalysisResult {
  final String suggestedName;
  final List<String> tags; // e.g. ["Wholesale", "iPhone 15", "VIP"]
  final String status; // 'New', 'Contacted', 'Qualified', 'Converted', 'Archived'
  final String interestSummary; // e.g. "Interested in bulk purchasing 50 units of Solar Inverters"
  final String lastPurchasedOrRequestedItem;
  final double confidenceScore;

  GeminiAnalysisResult({
    this.suggestedName = '',
    required this.tags,
    this.status = 'Qualified',
    this.interestSummary = '',
    this.lastPurchasedOrRequestedItem = '',
    this.confidenceScore = 1.0,
  });

  factory GeminiAnalysisResult.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'];
    final List<String> parsedTags = [];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t != null && t.toString().trim().isNotEmpty) {
          parsedTags.add(t.toString().trim());
        }
      }
    } else if (rawTags is String) {
      parsedTags.addAll(rawTags.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }

    return GeminiAnalysisResult(
      suggestedName: map['suggested_name']?.toString() ?? '',
      tags: parsedTags,
      status: map['status']?.toString() ?? 'Qualified',
      interestSummary: map['interest_summary']?.toString() ?? '',
      lastPurchasedOrRequestedItem: map['last_item']?.toString() ?? '',
      confidenceScore: (map['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class GeminiService {
  static const String _geminiApiKeyPref = 'gemini_api_key';
  static const String defaultModel = 'gemini-1.5-flash';
  
  /// Optional default hardcoded/env API key
  static const String defaultApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '', // You can paste your key directly here if you want it hardcoded
  );

  /// Retrieve stored Gemini API key
  static Future<String?> getApiKey() async {
    // 1. Check local SQLite preferences
    try {
      final db = await DatabaseService.database;
      final rows = await db.query(
        'app_preferences',
        columns: ['preference_value'],
        where: 'preference_key = ?',
        whereArgs: [_geminiApiKeyPref],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final key = rows.single['preference_value']?.toString().trim();
        if (key != null && key.isNotEmpty) return key;
      }
    } catch (_) {}

    // 2. Check root .env file asset if present
    try {
      final envFile = File('.env');
      if (await envFile.exists()) {
        final lines = await envFile.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('GEMINI_API_KEY=')) {
            final val = trimmed.substring('GEMINI_API_KEY='.length).trim().replaceAll('"', '').replaceAll("'", "");
            if (val.isNotEmpty) return val;
          }
        }
      }
    } catch (_) {}

    // 3. Check flutter rootBundle .env
    try {
      final bundleString = await rootBundle.loadString('.env');
      final lines = const LineSplitter().convert(bundleString);
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('GEMINI_API_KEY=')) {
          final val = trimmed.substring('GEMINI_API_KEY='.length).trim().replaceAll('"', '').replaceAll("'", "");
          if (val.isNotEmpty) return val;
        }
      }
    } catch (_) {}

    return defaultApiKey.isNotEmpty ? defaultApiKey : null;
  }

  /// Save Gemini API key
  static Future<void> saveApiKey(String apiKey) async {
    final db = await DatabaseService.database;
    await db.insert(
      'app_preferences',
      {
        'preference_key': _geminiApiKeyPref,
        'preference_value': apiKey.trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Check if Gemini AI is configured
  static Future<bool> isConfigured() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Analyse conversation messages and customer history for a lead
  static Future<GeminiAnalysisResult?> analyzeLeadChat({
    required Lead lead,
    required List<LeadMessage> messages,
    String? customPromptContext,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API key is not configured. Please enter your API key in Settings.');
    }

    // Build chat transcript text
    final buffer = StringBuffer();
    buffer.writeln('Customer Phone: ${lead.phoneNumber}');
    if (lead.name.isNotEmpty) buffer.writeln('Customer Name: ${lead.name}');
    if (lead.notes.isNotEmpty) buffer.writeln('Existing Notes: ${lead.notes}');
    if (lead.tags.isNotEmpty) buffer.writeln('Existing Tags: ${lead.tags}');
    buffer.writeln('\n--- CHAT TRANSCRIPT ---');

    if (messages.isEmpty) {
      buffer.writeln('(No detailed messages recorded yet. Relying on customer metadata and notes.)');
    } else {
      for (final msg in messages) {
        final sender = msg.direction == 'outgoing' ? 'Business/Agent' : 'Customer (${lead.phoneNumber})';
        final time = DateTime.fromMillisecondsSinceEpoch(msg.timestamp).toIso8601String();
        buffer.writeln('[$time] $sender: ${msg.message}');
        if (msg.note.isNotEmpty) {
          buffer.writeln('  (Internal Note: ${msg.note})');
        }
      }
    }

    final prompt = '''
You are an expert CRM & Sales AI Analyst.
Analyze the following WhatsApp conversation/customer interaction for phone number "${lead.phoneNumber}".

Your goals:
1. Identify the customer's specific interests, products requested, services inquired about, or items bought.
2. Determine appropriate categorical Tags (e.g., "Wholesale", "iPhone 15", "Real Estate", "Urgent", "VIP", "Pricing Inquiry").
3. Determine the customer's Lead Stage ("New", "Contacted", "Qualified", "Converted", "Archived").
4. Extract customer's real name if mentioned in chat.
5. Create a crisp, actionable 1-2 sentence Interest & Purchase Summary.

$buffer

${customPromptContext != null && customPromptContext.isNotEmpty ? 'Additional Business Guidelines: $customPromptContext' : ''}

Respond ONLY with a valid JSON object in the following format with NO markdown wrapping:
{
  "suggested_name": "Customer Name or empty",
  "tags": ["tag1", "tag2", "tag3"],
  "status": "New | Contacted | Qualified | Converted | Archived",
  "interest_summary": "1-2 sentence summary of requirements, interests, or purchase",
  "last_item": "Specific item or service requested",
  "confidence": 0.95
}
''';

    try {
      final client = createHttpClient();

      // Dynamically discover which models are available for this API key
      String? activeModel;
      try {
        final listModelsUri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
        );
        final listReq = await client.getUrl(listModelsUri);
        final listResp = await listReq.close();
        final listBody = await listResp.transform(utf8.decoder).join();
        if (listResp.statusCode == 200) {
          final listJson = jsonDecode(listBody) as Map<String, dynamic>;
          final modelsList = listJson['models'] as List?;
          if (modelsList != null && modelsList.isNotEmpty) {
            final validModels = modelsList.where((m) {
              final methods = (m['supportedGenerationMethods'] as List?)?.cast<String>() ?? [];
              return methods.contains('generateContent');
            }).map((m) => m['name']?.toString() ?? '').toList();

            // Prefer 1.5-flash, then 2.0-flash, then 1.5-pro, then gemini-pro, or first available
            activeModel = validModels.firstWhere(
              (m) => m.contains('1.5-flash'),
              orElse: () => validModels.firstWhere(
                (m) => m.contains('flash'),
                orElse: () => validModels.firstWhere(
                  (m) => m.contains('gemini-pro') || m.contains('1.5-pro'),
                  orElse: () => validModels.isNotEmpty ? validModels.first : 'models/gemini-1.5-flash',
                ),
              ),
            );
            if (activeModel.startsWith('models/')) {
              activeModel = activeModel.substring('models/'.length);
            }
          }
        } else {
          final errMap = tryDecodeJson(listBody);
          final errMsg = errMap?['error']?['message'];
          if (errMsg != null && errMsg.toString().isNotEmpty) {
            throw Exception('Gemini API: $errMsg');
          }
        }
      } catch (e) {
        debugPrint('Model listing error / fallback: $e');
        if (e.toString().startsWith('Exception: Gemini API:')) {
          rethrow;
        }
      }

      activeModel ??= defaultModel;

      Future<GeminiAnalysisResult?> attemptGenerate(String modelName) async {
        final endpoint = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
        );

        final payload = {
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.2,
            'responseMimeType': 'application/json',
          }
        };

        final response = await client.postUrl(endpoint).then((req) {
          req.headers.set('Content-Type', 'application/json');
          req.add(utf8.encode(jsonEncode(payload)));
          return req.close();
        });

        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode != 200) {
          final errMap = tryDecodeJson(responseBody);
          final errMsg = errMap?['error']?['message'] ?? 'Gemini API returned code ${response.statusCode}';
          throw Exception(errMsg);
        }

        final jsonRes = jsonDecode(responseBody) as Map<String, dynamic>;
        final candidates = jsonRes['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('Gemini returned no response candidates.');
        }

        final text = candidates.first['content']?['parts']?[0]?['text']?.toString() ?? '{}';
        final cleanText = text.replaceAll('```json', '').replaceAll('```', '').trim();
        final parsed = jsonDecode(cleanText) as Map<String, dynamic>;

        return GeminiAnalysisResult.fromMap(parsed);
      }

      return await attemptGenerate(activeModel);
    } catch (e) {
      debugPrint('GeminiService analysis error: $e');
      rethrow;
    }
  }

  /// Automatically applies analysis result to a Lead in SQLite database
  static Future<Lead> applyAnalysisToLead(Lead lead, GeminiAnalysisResult result) async {
    // Combine existing and new tags uniquely
    final existingTags = lead.tags.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    existingTags.addAll(result.tags);
    final combinedTags = existingTags.join(', ');

    // Combine notes
    var updatedNotes = lead.notes;
    if (result.interestSummary.isNotEmpty) {
      if (updatedNotes.isEmpty) {
        updatedNotes = '🤖 AI Summary: ${result.interestSummary}';
      } else if (!updatedNotes.contains(result.interestSummary)) {
        updatedNotes = '$updatedNotes\n🤖 AI Summary: ${result.interestSummary}';
      }
    }

    final updatedName = (lead.name.isEmpty && result.suggestedName.isNotEmpty)
        ? result.suggestedName
        : lead.name;

    final updatedLead = lead.copyWith(
      name: updatedName,
      tags: combinedTags,
      notes: updatedNotes,
      status: result.status.isNotEmpty ? result.status : lead.status,
      whatsappOptIn: true,
    );

    await DatabaseService.updateLead(updatedLead);
    return updatedLead;
  }

  static dynamic tryDecodeJson(String str) {
    try {
      return jsonDecode(str);
    } catch (_) {
      return null;
    }
  }

  static dynamic createHttpClient() {
    return HttpClient();
  }
}

// Helper to avoid sqflite conflict enum dependency in pure dart file
const sqfliteConflictAlgorithmReplace = 1;
