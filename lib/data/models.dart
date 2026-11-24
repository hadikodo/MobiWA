import 'dart:typed_data';

/// Kind of category. Unnamed and Junk always exist and cannot be deleted.
enum CategoryKind { unnamed, junk, custom }

class ContactCategory {
  final int id;
  final String userId;
  final String name;
  final CategoryKind kind;
  final String description;
  final int count;

  const ContactCategory({
    required this.id,
    required this.userId,
    required this.name,
    required this.kind,
    this.description = '',
    this.count = 0,
  });

  bool get isSystem => kind != CategoryKind.custom;

  factory ContactCategory.fromRow(Map<String, dynamic> r) {
    // Embedded count from PostgREST: contacts: [{count: n}]
    final embedded = r['contacts'];
    final count = embedded is List && embedded.isNotEmpty
        ? (embedded.first['count'] as num).toInt()
        : (r['cnt'] as num?)?.toInt() ?? 0;
    return ContactCategory(
      id: (r['id'] as num).toInt(),
      userId: r['user_id'] as String,
      name: r['name'] as String,
      kind: CategoryKind.values.byName(r['kind'] as String),
      description: (r['description'] as String?) ?? '',
      count: count,
    );
  }
}

/// What happened when the AI looked at a number.
enum AiStatus {
  /// Not looked at yet.
  pending,

  /// AI decided: customer (in a category) or Junk.
  sorted,

  /// Chat could not be read (no messages); stays in Unnamed and is retried.
  skipped,

  /// AI call failed; stays in Unnamed and is retried.
  error,
}

class Contact {
  final int id;
  final String userId;
  final String phone;
  final String name;
  final int categoryId;
  final String sourceApp;
  final AiStatus aiStatus;
  final String aiReason;
  final DateTime createdAt;

  const Contact({
    required this.id,
    required this.userId,
    required this.phone,
    required this.name,
    required this.categoryId,
    required this.sourceApp,
    required this.aiStatus,
    required this.aiReason,
    required this.createdAt,
  });

  String get label => name.isNotEmpty ? name : phone;

  factory Contact.fromRow(Map<String, dynamic> r) => Contact(
        id: (r['id'] as num).toInt(),
        userId: r['user_id'] as String,
        phone: r['phone'] as String,
        name: (r['name'] as String?) ?? '',
        categoryId: (r['category_id'] as num).toInt(),
        sourceApp: (r['source_app'] as String?) ?? '',
        aiStatus: AiStatus.values.byName((r['ai_status'] as String?) ?? 'pending'),
        aiReason: (r['ai_reason'] as String?) ?? '',
        createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
      );
}

/// A WhatsApp app installed on the phone.
enum WaApp {
  normal('com.whatsapp', 'WhatsApp'),
  business('com.whatsapp.w4b', 'WhatsApp Business');

  const WaApp(this.package, this.label);
  final String package;
  final String label;

  static WaApp? fromPackage(String? p) {
    for (final a in WaApp.values) {
      if (a.package == p) return a;
    }
    return null;
  }
}

/// Type of message to send.
enum MessageType {
  text('Text', 'text/plain'),
  image('Image', 'image/*'),
  video('Video', 'video/*'),
  pdf('PDF', 'application/pdf');

  const MessageType(this.label, this.pickerMime);
  final String label;
  final String pickerMime;

  bool get hasMedia => this != MessageType.text;
}

/// A file picked for sending, copied into app storage.
class PickedMedia {
  /// Android: file copied into app storage. Web: empty (see [bytes]).
  final String path;
  final String name;
  final String mime;
  final int size;

  /// Web: the file contents, handed to the extension for WhatsApp Web.
  final Uint8List? bytes;

  const PickedMedia({
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
    this.bytes,
  });

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// One message read from a WhatsApp chat.
typedef ChatMessage = ({String text, bool fromCustomer, String time});

enum Role { user, admin }

/// A MobiWA account (row in public.profiles).
class Profile {
  final String id;
  final String username;
  final String fullName;
  final Role role;
  final bool active;
  final String businessName;
  final String businessDescription;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;

  /// Phone the account is signed in on ('' = signed out everywhere).
  final String deviceName;
  final DateTime? deviceBoundAt;

  const Profile({
    required this.id,
    required this.username,
    this.fullName = '',
    this.role = Role.user,
    this.active = true,
    this.businessName = '',
    this.businessDescription = '',
    this.createdAt,
    this.lastSeenAt,
    this.deviceName = '',
    this.deviceBoundAt,
  });

  bool get isAdmin => role == Role.admin;
  bool get signedIn => deviceBoundAt != null;
  String get displayName => fullName.isNotEmpty ? fullName : username;

  factory Profile.fromRow(Map<String, dynamic> r) => Profile(
        id: (r['id'] ?? r['user_id']) as String,
        username: r['username'] as String,
        fullName: (r['full_name'] as String?) ?? '',
        role: r['role'] == 'admin' ? Role.admin : Role.user,
        active: (r['active'] as bool?) ?? true,
        businessName: (r['business_name'] as String?) ?? '',
        businessDescription: (r['business_description'] as String?) ?? '',
        createdAt: DateTime.tryParse('${r['created_at']}'),
        lastSeenAt: DateTime.tryParse('${r['last_seen_at']}'),
        deviceName: (r['device_name'] as String?) ?? '',
        deviceBoundAt: DateTime.tryParse('${r['device_bound_at']}'),
      );
}

/// Per-user totals for the admin panel (public.admin_user_stats()).
class UserStats {
  final Profile profile;
  final int numbers;
  final int unnamed;
  final int customers;
  final int junk;
  final int categories;
  final int messagesSent;

  const UserStats({
    required this.profile,
    required this.numbers,
    required this.unnamed,
    required this.customers,
    required this.junk,
    required this.categories,
    required this.messagesSent,
  });

  factory UserStats.fromRow(Map<String, dynamic> r) {
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    return UserStats(
      profile: Profile.fromRow(r),
      numbers: n('numbers'),
      unnamed: n('unnamed'),
      customers: n('customers'),
      junk: n('junk'),
      categories: n('categories'),
      messagesSent: n('messages_sent'),
    );
  }
}

/// One day of activity across all users (public.admin_daily_activity()).
class DayActivity {
  final DateTime day;
  final int numbersFound;
  final int sorted;
  final int messagesSent;

  const DayActivity(this.day, this.numbersFound, this.sorted, this.messagesSent);

  factory DayActivity.fromRow(Map<String, dynamic> r) => DayActivity(
        DateTime.parse(r['day'] as String),
        (r['numbers_found'] as num).toInt(),
        (r['sorted'] as num).toInt(),
        (r['messages_sent'] as num).toInt(),
      );
}

/// A contact saved in the phone's address book.
class PhoneContact {
  final String name;

  /// As stored on the phone; international ("+961…") when Android or WhatsApp
  /// knows it, otherwise as typed (normalised with the country code later).
  final String phone;
  final bool onWhatsApp;
  final bool business;

  const PhoneContact({
    required this.name,
    required this.phone,
    required this.onWhatsApp,
    required this.business,
  });

  String get label => name.isNotEmpty ? name : phone;

  factory PhoneContact.fromMap(Map m) => PhoneContact(
        name: '${m['name'] ?? ''}',
        phone: '${m['phone'] ?? ''}',
        onWhatsApp: m['whatsapp'] == true,
        business: m['business'] == true,
      );
}

/// A message sent from the "Contact us" form on the website.
class ContactMessage {
  final int id;
  final String name;
  final String email;
  final String business;
  final String topic;
  final String message;
  final bool handled;
  final DateTime createdAt;

  const ContactMessage({
    required this.id,
    required this.name,
    required this.email,
    required this.business,
    required this.topic,
    required this.message,
    required this.handled,
    required this.createdAt,
  });

  factory ContactMessage.fromRow(Map<String, dynamic> r) => ContactMessage(
        id: (r['id'] as num).toInt(),
        name: '${r['name']}',
        email: '${r['email']}',
        business: '${r['business'] ?? ''}',
        topic: '${r['topic'] ?? 'general'}',
        message: '${r['message']}',
        handled: r['handled'] == true,
        createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
      );
}
