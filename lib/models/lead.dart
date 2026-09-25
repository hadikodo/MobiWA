// lib/models/lead.dart

class Lead {
  final int? id;
  final String phoneNumber;
  final String name;
  final String notes;
  final String status; // 'New', 'Contacted', 'Qualified', 'Converted', 'Archived'
  final bool isUnsaved;
  final String tags;
  final int createdAt;
  final int updatedAt;
  final int messageCount;
  final String? lastMessage;
  final int? lastMessageTime;

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
    this.messageCount = 0,
    this.lastMessage,
    this.lastMessageTime,
  });

  DateTime get createdDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt);
  DateTime get updatedDateTime =>
      DateTime.fromMillisecondsSinceEpoch(updatedAt);
  DateTime? get lastMessageDateTime => lastMessageTime != null
      ? DateTime.fromMillisecondsSinceEpoch(lastMessageTime!)
      : null;

  String get displayName => name.trim().isNotEmpty ? name.trim() : phoneNumber;

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
    messageCount: (map['message_count'] as int?) ?? 0,
    lastMessage: map['last_message'] as String?,
    lastMessageTime: map['last_message_time'] as int?,
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
    int? messageCount,
    String? lastMessage,
    int? lastMessageTime,
  }) => Lead(
    id: id ?? this.id,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    isUnsaved: isUnsaved ?? this.isUnsaved,
    tags: tags ?? this.tags,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    messageCount: messageCount ?? this.messageCount,
    lastMessage: lastMessage ?? this.lastMessage,
    lastMessageTime: lastMessageTime ?? this.lastMessageTime,
  );
}
