// lib/models/lead_message.dart

class LeadMessage {
  final int? id;
  final int leadId;
  final String phoneNumber;
  final String message;
  final String direction; // 'incoming' | 'outgoing'
  final int timestamp;
  final String note;

  LeadMessage({
    this.id,
    required this.leadId,
    required this.phoneNumber,
    required this.message,
    this.direction = 'incoming',
    required this.timestamp,
    this.note = '',
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'lead_id': leadId,
    'phone_number': phoneNumber,
    'message': message,
    'direction': direction,
    'timestamp': timestamp,
    'note': note,
  };

  factory LeadMessage.fromMap(Map<String, dynamic> map) => LeadMessage(
    id: map['id'] as int?,
    leadId: map['lead_id'] as int,
    phoneNumber: map['phone_number'] as String,
    message: map['message'] as String,
    direction: map['direction'] as String? ?? 'incoming',
    timestamp: map['timestamp'] as int,
    note: map['note'] as String? ?? '',
  );

  LeadMessage copyWith({
    int? id,
    int? leadId,
    String? phoneNumber,
    String? message,
    String? direction,
    int? timestamp,
    String? note,
  }) => LeadMessage(
    id: id ?? this.id,
    leadId: leadId ?? this.leadId,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    message: message ?? this.message,
    direction: direction ?? this.direction,
    timestamp: timestamp ?? this.timestamp,
    note: note ?? this.note,
  );
}
