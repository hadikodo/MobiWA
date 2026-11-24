import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/settings.dart';
import 'gemini.dart';
import 'native.dart';

/// Base for the three long-running actions. Only one can run at a time
/// because the phone can only show one WhatsApp screen.
abstract class Job extends ChangeNotifier {
  bool running = false;
  bool finished = false;
  bool stopRequested = false;
  String? error;
  StreamSubscription<void>? _stopSub;

  String get title;

  static final scan = ScanJob();
  static final sort = SortJob();
  static final send = SendJob();
  static List<Job> get all => [scan, sort, send];

  static Job? get active {
    for (final j in all) {
      if (j.running) return j;
    }
    return null;
  }

  @protected
  bool begin() {
    if (active != null) return false;
    running = true;
    finished = false;
    stopRequested = false;
    error = null;
    _stopSub = Native.stopRequests.listen((_) => stop());
    notifyListeners();
    return true;
  }

  @protected
  Future<void> end() async {
    await _stopSub?.cancel();
    _stopSub = null;
    try {
      await Native.hideOverlay();
      await Native.returnToApp();
    } catch (_) {}
    running = false;
    finished = true;
    notifyListeners();
  }

  void stop() {
    if (!running || stopRequested) return;
    stopRequested = true;
    Native.cancelJob().catchError((_) {});
    notifyListeners();
  }

  /// Clears the "finished" summary so the screen shows its start state again.
  void reset() {
    if (running) return;
    finished = false;
    error = null;
    notifyListeners();
  }

  static String friendlyError(Object e) {
    if (e is PlatformException) return e.message ?? e.code;
    return e.toString().replaceFirst('Exception: ', '');
  }
}

// ---------------------------------------------------------------------------
// 1 · Get numbers
// ---------------------------------------------------------------------------

class ScanJob extends Job {
  WaApp? app;
  int foundSoFar = 0;
  int found = 0;
  int added = 0;
  StreamSubscription<int>? _progressSub;

  @override
  String get title => 'Getting numbers';

  Future<void> start(WaApp whatsapp) async {
    if (!begin()) return;
    app = whatsapp;
    foundSoFar = found = added = 0;
    _progressSub = Native.scanProgress.listen((n) {
      foundSoFar = n;
      notifyListeners();
    });
    try {
      await Native.showOverlay('Getting numbers from ${whatsapp.label}…');
      final numbers = await Native.scanUnsaved(whatsapp);
      found = numbers.length;
      added = await Db.addUnnamed(numbers, whatsapp.package);
      await Settings.setLastApp(whatsapp);
      await Db.logActivity('scan', {'found': found, 'added': added, 'app': whatsapp.package});
    } catch (e, s) {
      debugPrint('MobiWA scan failed: $e\n$s');
      error = Job.friendlyError(e);
    } finally {
      await _progressSub?.cancel();
      await end();
    }
  }
}

// ---------------------------------------------------------------------------
// 2 · AI sort
// ---------------------------------------------------------------------------

enum SortOutcome { customer, junk, skipped, failed }

class SortLogEntry {
  final String phone;
  final SortOutcome outcome;
  final String detail; // category name or reason
  const SortLogEntry(this.phone, this.outcome, this.detail);
}

class SortJob extends Job {
  int total = 0;
  int done = 0;
  String current = '';
  final List<SortLogEntry> log = [];

  @override
  String get title => 'AI sorting';

  int count(SortOutcome o) => log.where((e) => e.outcome == o).length;

  /// Sorts everything in Unnamed, or only [only] (e.g. picked phone contacts),
  /// reading chats in [app] when given (else each number's own WhatsApp).
  Future<void> start({List<Contact>? only, WaApp? app}) async {
    final contacts = only ?? await Db.contactsIn(Db.unnamedId);
    if (contacts.isEmpty) return;
    if (!begin()) return;

    total = contacts.length;
    done = 0;
    log.clear();
    final business = await Settings.business();
    final fallbackApp = await Settings.lastApp() ?? WaApp.normal;
    final forcedApp = app;

    try {
      await Native.showOverlay('AI sorting 0 of $total');

      for (final c in contacts) {
        if (stopRequested) break;
        current = c.label;
        notifyListeners();
        await Native.updateOverlay('AI sorting ${done + 1} of $total · ${c.label}');

        final app = forcedApp ?? WaApp.fromPackage(c.sourceApp) ?? fallbackApp;
        final entry = await _sortOne(c, app, business);
        if (stopRequested && entry.outcome == SortOutcome.skipped) break;
        log.insert(0, entry);
        done++;
        notifyListeners();
      }
    } on AiFatalError catch (e) {
      debugPrint('MobiWA sort stopped: ${e.message}');
      error = e.message;
    } catch (e, s) {
      debugPrint('MobiWA sort failed: $e\n$s');
      error = Job.friendlyError(e);
    } finally {
      current = '';
      if (done > 0) {
        await Db.logActivity('sort', {
          'customers': count(SortOutcome.customer),
          'junk': count(SortOutcome.junk),
          'skipped': count(SortOutcome.skipped) + count(SortOutcome.failed),
        });
      }
      await end();
    }
  }

  Future<SortLogEntry> _sortOne(Contact c, WaApp app, String business) async {
    final chat = await Native.readChat(c.phone, app);
    // Stopped mid-read: don't judge a half-read chat, leave the number as it was.
    if (stopRequested) return SortLogEntry(c.label, SortOutcome.skipped, 'Stopped');

    if (chat.notOnWhatsApp) {
      await Db.saveAiResult(
          contactId: c.id, categoryId: Db.junkId, status: AiStatus.sorted, reason: 'Not on WhatsApp');
      return SortLogEntry(c.label, SortOutcome.junk, 'Not on WhatsApp');
    }
    debugPrint('MobiWA read ${c.phone}: ${chat.messages.length} messages'
        '${chat.notOnWhatsApp ? ' (not on WhatsApp)' : ''}');
    if (chat.messages.isEmpty) {
      await Db.saveAiResult(
          contactId: c.id,
          categoryId: c.categoryId, // keep where it was
          status: AiStatus.skipped,
          reason: 'No messages could be read — will retry next time');
      return SortLogEntry(c.label, SortOutcome.skipped, 'No messages found');
    }

    try {
      final decision = await Gemini.classify(
        phone: c.phone,
        messages: chat.messages,
        existing: await Db.categories(),
        business: business,
      );
      if (decision.isCustomer) {
        final catId = await Db.categoryIdFor(decision.category,
            description: decision.categoryDescription);
        await Db.saveAiResult(
          contactId: c.id,
          categoryId: catId,
          status: AiStatus.sorted,
          reason: decision.reason,
          // Keep a name the user saved on the phone; else use one the AI found.
          name: c.name.isEmpty ? decision.name : '',
        );
        return SortLogEntry(c.label, SortOutcome.customer, decision.category);
      }
      await Db.saveAiResult(
          contactId: c.id, categoryId: Db.junkId, status: AiStatus.sorted, reason: decision.reason);
      return SortLogEntry(c.label, SortOutcome.junk, decision.reason);
    } on AiFatalError {
      rethrow;
    } catch (e) {
      debugPrint('MobiWA sort ${c.phone}: $e');
      await Db.saveAiResult(
          contactId: c.id,
          categoryId: c.categoryId, // keep where it was
          status: AiStatus.error,
          reason: Job.friendlyError(e));
      return SortLogEntry(c.label, SortOutcome.failed, Job.friendlyError(e));
    }
  }
}

// ---------------------------------------------------------------------------
// 3 · Send messages
// ---------------------------------------------------------------------------

enum SendStatus { waiting, sending, sent, notOnWhatsApp, failed, skipped }

class SendJob extends Job {
  WaApp app = WaApp.normal;
  String text = '';
  PickedMedia? media;
  List<String> recipients = [];
  final Map<String, SendStatus> status = {};
  final Map<String, String> failReason = {};
  int index = 0;
  int secondsUntilNext = 0;

  @override
  String get title => 'Sending messages';

  int count(SendStatus s) => status.values.where((v) => v == s).length;
  List<String> get failed => recipients
      .where((p) => status[p] == SendStatus.failed || status[p] == SendStatus.skipped)
      .toList();

  Future<void> start({
    required WaApp app,
    required List<String> recipients,
    required String text,
    PickedMedia? media,
  }) async {
    if (recipients.isEmpty) return;
    if (!begin()) return;
    this.app = app;
    this.recipients = List.of(recipients);
    this.text = text;
    this.media = media;
    status
      ..clear()
      ..addEntries(recipients.map((p) => MapEntry(p, SendStatus.waiting)));
    failReason.clear();
    index = 0;
    await Settings.setLastApp(app);
    final delay = await Settings.sendDelay();
    final rnd = Random();

    try {
      await Native.showOverlay('Sending 1 of ${recipients.length}');
      for (index = 0; index < this.recipients.length; index++) {
        if (stopRequested) break;
        final phone = this.recipients[index];
        status[phone] = SendStatus.sending;
        notifyListeners();
        await Native.updateOverlay('Sending ${index + 1} of ${this.recipients.length} · $phone');

        final r = await Native.sendMessage(phone: phone, app: app, text: text, media: media);
        if (r == 'sent') {
          status[phone] = SendStatus.sent;
        } else if (r == 'not_on_whatsapp') {
          status[phone] = SendStatus.notOnWhatsApp;
        } else if (r == 'cancelled') {
          status[phone] = SendStatus.skipped;
        } else {
          status[phone] = SendStatus.failed;
          failReason[phone] = _reasonText(r);
        }
        debugPrint('MobiWA send $phone: $r');
        notifyListeners();

        // Pause between messages (with a little randomness) to look human
        // and give WhatsApp time to settle.
        if (index < this.recipients.length - 1 && !stopRequested) {
          final wait = delay + rnd.nextInt(3);
          for (secondsUntilNext = wait; secondsUntilNext > 0 && !stopRequested; secondsUntilNext--) {
            await Native.updateOverlay(
                'Sent ${count(SendStatus.sent)} of ${this.recipients.length} · next in ${secondsUntilNext}s');
            notifyListeners();
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          secondsUntilNext = 0;
        }
      }
      for (final p in this.recipients) {
        if (status[p] == SendStatus.waiting || status[p] == SendStatus.sending) {
          status[p] = SendStatus.skipped;
        }
      }
    } catch (e, s) {
      debugPrint('MobiWA send failed: $e\n$s');
      error = Job.friendlyError(e);
    } finally {
      await Db.logActivity('send', {
        'total': this.recipients.length,
        'sent': count(SendStatus.sent),
        'failed': count(SendStatus.failed),
        'not_on_whatsapp': count(SendStatus.notOnWhatsApp),
        'type': media == null ? 'text' : media.mime,
      });
      await end();
    }
  }

  /// Sends the same message again to the numbers that failed or were skipped.
  Future<void> retryFailed() =>
      start(app: app, recipients: failed, text: text, media: media);

  static String _reasonText(String code) {
    final c = code.replaceFirst('failed:', '');
    return switch (c) {
      'timeout' => 'WhatsApp took too long',
      'send_button_not_found' => 'Could not find the Send button',
      'send_not_confirmed' => 'Send was not confirmed',
      'file_missing' => 'The attached file is missing',
      'cannot_open_whatsapp' => 'Could not open WhatsApp',
      'busy' => 'Another action was running',
      _ => c,
    };
  }
}
