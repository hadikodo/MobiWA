// lib/models/lead.dart

class Lead {
  final int? id;
  final String phoneNumber;
  final String name;
  final String notes;
  final String
      status; // 'New', 'Contacted', 'Qualified', 'Converted', 'Archived'
  final bool isUnsaved;
  final String tags;
  final int createdAt;
  final int updatedAt;
  final bool whatsappOptIn;
  final int? whatsappConsentUpdatedAt;
  final int messageCount;
  final String? lastMessage;
  final int? lastMessageTime;

  /// Mobi AI CRM list this customer belongs to (e.g. 'Hot Leads'). Empty = not analyzed.
  final String aiList;
  final String aiSummary;
  final String aiNextAction;
  final int? aiAnalyzedAt;

  Lead({
    this.id,
    required this.phoneNumber,
    this.name = '',
    this.notes = '',
    this.status = 'New',
    this.isUnsaved = true,
    this.tags = '',
    required this.createdAt,
    required this.updatedAt,
    this.whatsappOptIn = false,
    this.whatsappConsentUpdatedAt,
    this.messageCount = 0,
    this.lastMessage,
    this.lastMessageTime,
    this.aiList = '',
    this.aiSummary = '',
    this.aiNextAction = '',
    this.aiAnalyzedAt,
  });

  DateTime get createdDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt);
  DateTime get updatedDateTime =>
      DateTime.fromMillisecondsSinceEpoch(updatedAt);
  DateTime? get lastMessageDateTime => lastMessageTime != null
      ? DateTime.fromMillisecondsSinceEpoch(lastMessageTime!)
      : null;

  String get displayName => name.trim().isNotEmpty ? name.trim() : phoneNumber;

  /// Dynamic CRM & product segment lists this customer belongs to
  /// (e.g. ['Customers', 'Oil Filter Customers', 'VIP Customers'])
  List<String> get aiLists {
    if (aiList.trim().isEmpty) return const [];
    return aiList
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  /// Checks if this lead belongs to a specific CRM / product list
  bool isInList(String listName) {
    final target = listName.trim().toLowerCase();
    return aiLists.any((l) => l.toLowerCase() == target);
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'phone_number': phoneNumber,
        'name': name,
        'notes': notes,
        'status': status,
        'is_unsaved': isUnsaved ? 1 : 0,
        'tags': tags,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'whatsapp_opt_in': whatsappOptIn ? 1 : 0,
        'whatsapp_consent_updated_at': whatsappConsentUpdatedAt,
        'ai_list': aiList,
        'ai_summary': aiSummary,
        'ai_next_action': aiNextAction,
        'ai_analyzed_at': aiAnalyzedAt,
      };

  factory Lead.fromMap(Map<String, dynamic> map) => Lead(
        id: map['id'] as int?,
        phoneNumber: (map['phone_number'] ?? map['sender'] ?? '') as String,
        name: map['name'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        status: map['status'] as String? ?? 'New',
        isUnsaved: ((map['is_unsaved'] as int?) ?? 1) == 1,
        tags: map['tags'] as String? ?? '',
        createdAt: (map['created_at'] ?? map['timestamp'] ?? 0) as int,
        updatedAt: (map['updated_at'] ?? map['timestamp'] ?? 0) as int,
        whatsappOptIn: ((map['whatsapp_opt_in'] as int?) ?? 0) == 1,
        whatsappConsentUpdatedAt: map['whatsapp_consent_updated_at'] as int?,
        messageCount: (map['message_count'] as int?) ?? 0,
        lastMessage: map['last_message'] as String?,
        lastMessageTime: map['last_message_time'] as int?,
        aiList: map['ai_list'] as String? ?? '',
        aiSummary: map['ai_summary'] as String? ?? '',
        aiNextAction: map['ai_next_action'] as String? ?? '',
        aiAnalyzedAt: map['ai_analyzed_at'] as int?,
      );

  Lead copyWith({
    int? id,
    String? phoneNumber,
    String? name,
    String? notes,
    String? status,
    bool? isUnsaved,
    String? tags,
    int? createdAt,
    int? updatedAt,
    bool? whatsappOptIn,
    int? whatsappConsentUpdatedAt,
    int? messageCount,
    String? lastMessage,
    int? lastMessageTime,
    String? aiList,
    String? aiSummary,
    String? aiNextAction,
    int? aiAnalyzedAt,
  }) =>
      Lead(
        id: id ?? this.id,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        name: name ?? this.name,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        isUnsaved: isUnsaved ?? this.isUnsaved,
        tags: tags ?? this.tags,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        whatsappOptIn: whatsappOptIn ?? this.whatsappOptIn,
        whatsappConsentUpdatedAt:
            whatsappConsentUpdatedAt ?? this.whatsappConsentUpdatedAt,
        messageCount: messageCount ?? this.messageCount,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageTime: lastMessageTime ?? this.lastMessageTime,
        aiList: aiList ?? this.aiList,
        aiSummary: aiSummary ?? this.aiSummary,
        aiNextAction: aiNextAction ?? this.aiNextAction,
        aiAnalyzedAt: aiAnalyzedAt ?? this.aiAnalyzedAt,
      );
}
