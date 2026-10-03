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
  final List<String> customerLists; // e.g. ["Customers", "Oil Filter Customers", "VIP Customers"]
  final String interestSummary; // e.g. "Interested in bulk purchasing 50 units of Solar Inverters"
  final String lastPurchasedOrRequestedItem;
  final String nextAction; // Recommended next sales / follow-up action
  final double confidenceScore;

  String get customerList =>
      customerLists.isNotEmpty ? customerLists.first : 'Warm Inquiries';
  String get customerListsFormatted => customerLists.join(', ');

  GeminiAnalysisResult({
    this.suggestedName = '',
    required this.tags,
    this.status = 'Qualified',
    List<String>? customerLists,
    String? customerList,
    this.interestSummary = '',
    this.lastPurchasedOrRequestedItem = '',
    this.nextAction = '',
    this.confidenceScore = 1.0,
  }) : customerLists = customerLists != null && customerLists.isNotEmpty
            ? customerLists
            : (customerList != null && customerList.trim().isNotEmpty
                ? [customerList.trim()]
                : const ['Warm Inquiries']);

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

    // Parse multi-lists
    final List<String> parsedLists = [];
    final rawLists = map['customer_lists'] ?? map['lists'];
    if (rawLists is List) {
      for (final l in rawLists) {
        if (l != null && l.toString().trim().isNotEmpty) {
          parsedLists.add(l.toString().trim());
        }
      }
    } else if (rawLists is String && rawLists.trim().isNotEmpty) {
      parsedLists.addAll(rawLists.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }

    final singleList = map['customer_list']?.toString().trim() ??
        map['list']?.toString().trim() ??
        '';
    if (singleList.isNotEmpty && !parsedLists.contains(singleList)) {
      parsedLists.add(singleList);
    }
    if (parsedLists.isEmpty) {
      parsedLists.add('Warm Inquiries');
    }

    return GeminiAnalysisResult(
      suggestedName: map['suggested_name']?.toString() ?? '',
      tags: parsedTags,
      status: map['status']?.toString() ?? 'Qualified',
      customerLists: parsedLists,
      interestSummary: map['interest_summary']?.toString() ?? '',
      lastPurchasedOrRequestedItem: map['last_item']?.toString() ?? '',
      nextAction: map['next_action']?.toString() ?? '',
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

  static const List<String> standardCustomerLists = [
    'Hot Leads',
    'VIP Customers',
    'Warm Inquiries',
    'Converted',
    'Cold / Follow-Up',
    'Support',
  ];

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
You are "Mobi AI", the intelligent CRM and sales intelligence engine of MobiWA.
Analyze the following WhatsApp conversation/customer interaction for phone number "${lead.phoneNumber}".

Your CRM categorization objectives:
1. Dynamic Multi-List Segmentation:
   Identify ALL products, parts, items, services, or topics discussed, purchased, or inquired about (e.g. "Oil Filter", "Brake Pads", "Engine Oil", "iPhone 15", "Solar Inverter").
   Categorize this customer into MULTIPLE ready-to-target broadcast lists:
   - If they bought/paid: include "Customers" AND "[Item] Customers" (e.g. "Oil Filter Customers").
   - If they asked/inquired: include "[Item] Inquiries" or "Warm Inquiries".
   - Include lifecycle / sales tier: "Hot Leads" (urgent buyer), "VIP Customers" (high-volume/wholesale), "Converted", "Support", or "Cold / Follow-Up".
   Example: If a customer bought an oil filter and asked about wholesale brake pads, your customer_lists MUST be:
   ["Customers", "Oil Filter Customers", "Brake Pad Inquiries", "VIP Customers"]

2. Suggest specific categorical tags (e.g. "Oil Filter", "Wholesale", "Urgent", "COD").
3. Extract the customer's real name if they introduced themselves or were addressed by name.
4. Create a crisp 1-2 sentence Interest & Purchase Summary.
5. Identify the exact specific item or service requested or purchased ("last_item").
6. Provide a concrete, actionable "next_action" for the sales team.

$buffer

${customPromptContext != null && customPromptContext.isNotEmpty ? 'Additional Business Guidelines: $customPromptContext' : ''}

Respond ONLY with a valid JSON object in the following format with NO markdown wrapping:
{
  "suggested_name": "Customer Name or empty",
  "customer_lists": ["Customers", "Oil Filter Customers", "VIP Customers"],
  "tags": ["tag1", "tag2", "tag3"],
  "status": "New | Contacted | Qualified | Converted | Archived",
  "interest_summary": "1-2 sentence summary of requirements, interests, or purchase",
  "last_item": "Specific item or service requested or bought",
  "next_action": "Actionable next step for sales or follow-up",
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
      aiList: result.customerListsFormatted.isNotEmpty
          ? result.customerListsFormatted
          : lead.aiList,
      aiSummary: result.interestSummary.isNotEmpty ? result.interestSummary : lead.aiSummary,
      aiNextAction: result.nextAction.isNotEmpty ? result.nextAction : lead.aiNextAction,
      aiAnalyzedAt: DateTime.now().millisecondsSinceEpoch,
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

  /// Generates natural text using Gemini for auto-replies, summaries, etc.
  static Future<String?> generateText({
    required String prompt,
    double temperature = 0.4,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API key is not configured.');
    }

    final client = createHttpClient();
    const model = defaultModel;
    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
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
        'temperature': temperature,
      }
    };

    try {
      final req = await client.postUrl(endpoint);
      req.headers.set('Content-Type', 'application/json');
      req.add(utf8.encode(jsonEncode(payload)));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final candidates = json['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates.first['content'];
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return parts.first['text']?.toString().trim();
          }
        }
      } else {
        final errMap = tryDecodeJson(body);
        final msg = errMap?['error']?['message'] ?? 'Error ${resp.statusCode}';
        debugPrint('Gemini generateText error: $msg');
      }
    } catch (e) {
      debugPrint('Gemini generateText failed: $e');
    }
    return null;
  }

  static dynamic _testHttpClient;

  static void setHttpClientForTesting(dynamic client) {
    _testHttpClient = client;
  }

  static dynamic createHttpClient() {
    return _testHttpClient ?? HttpClient();
  }
}
