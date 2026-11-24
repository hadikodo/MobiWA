import 'dart:async';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/jobs.dart';

/// Loads data with [load] and reloads it when [Db.revision] changes.
///
/// - Errors are caught here, so a failed request never becomes an "uncaught
///   exception" (which pauses the app under the debugger and freezes it).
/// - Reloads are batched (one per [debounce]) and postponed while an action
///   (scan / AI sort / send) is running, so screens kept alive in the
///   background don't hit the server after every single number.
class LiveData<T> extends StatefulWidget {
  const LiveData({
    super.key,
    required this.load,
    required this.builder,
    this.debounce = const Duration(seconds: 2),
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Duration debounce;

  @override
  State<LiveData<T>> createState() => _LiveDataState<T>();
}

class _LiveDataState<T> extends State<LiveData<T>> {
  T? _data;
  Object? _error;
  bool _loading = false;
  bool _reloadQueued = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Db.revision.addListener(_onChanged);
    _reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    Db.revision.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      if (!mounted) return;
      if (Job.active != null) {
        _onChanged(); // try again after the action finishes
        return;
      }
      _reload();
    });
  }

  Future<void> _reload() async {
    if (_loading) {
      _reloadQueued = true;
      return;
    }
    _loading = true;
    try {
      final data = await widget.load();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e, s) {
      debugPrint('MobiWA load failed: $e\n$s');
      if (mounted) setState(() => _error = e);
    } finally {
      _loading = false;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null) {
      return Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text('Could not refresh: ${Job.friendlyError(_error!)}'),
              actions: [TextButton(onPressed: _reload, child: const Text('Retry'))],
            ),
          Expanded(child: widget.builder(context, data, _reload)),
        ],
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded,
                size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('Could not load', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(Job.friendlyError(_error!), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _reload, child: const Text('Try again')),
          ]),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}
