// lib/models/lead.dart

class Lead {
  final int? id;
  final String sender;       // Phone number or name from notification
  final String message;      // Message body
  final int timestamp;       // Unix ms
  final bool isUnsaved;      // True if sender not in device contacts
  final bool isGroup;        // True if from a group chat
  final String source;       // 'notification' | 'backup'
  final String packageName;  // com.whatsapp or com.whatsapp.w4b

  Lead({
    this.id,
    required this.sender,
    required this.message,
    required this.timestamp,
    this.isUnsaved = false,
    this.isGroup = false,
    this.source = 'notification',
    this.packageName = 'com.whatsapp',
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  Map<String, dynamic> toMap() => {
    'id': id,
    'sender': sender,
    'message': message,
    'timestamp': timestamp,
    'is_unsaved': isUnsaved ? 1 : 0,
    'is_group': isGroup ? 1 : 0,
    'source': source,
    'package_name': packageName,
  };

  factory Lead.fromMap(Map<String, dynamic> m) => Lead(
    id: m['id'] as int?,
    sender: m['sender'] as String,
    message: m['message'] as String,
    timestamp: m['timestamp'] as int,
    isUnsaved: (m['is_unsaved'] as int) == 1,
    isGroup: (m['is_group'] as int) == 1,
    source: m['source'] as String? ?? 'notification',
    packageName: m['package_name'] as String? ?? 'com.whatsapp',
  );

  Lead copyWith({bool? isUnsaved}) => Lead(
    id: id,
    sender: sender,
    message: message,
    timestamp: timestamp,
    isUnsaved: isUnsaved ?? this.isUnsaved,
    isGroup: isGroup,
    source: source,
    packageName: packageName,
  );
}
