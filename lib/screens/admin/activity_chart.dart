import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

enum _Metric {
  found('Numbers found', AppColors.scan),
  sorted('AI sorted', AppColors.ai),
  sent('Messages sent', AppColors.send);

  const _Metric(this.label, this.color);
  final String label;
  final Color color;
}

/// Daily bars for one metric at a time (switch above the chart).
/// Tap a bar to read its exact value.
class ActivityChart extends StatefulWidget {
  const ActivityChart({super.key, required this.days});
  final List<DayActivity> days;

  @override
  State<ActivityChart> createState() => _ActivityChartState();
}

class _ActivityChartState extends State<ActivityChart> {
  _Metric _metric = _Metric.sent;
  int? _selected;

  int _value(DayActivity d) => switch (_metric) {
        _Metric.found => d.numbersFound,
        _Metric.sorted => d.sorted,
        _Metric.sent => d.messagesSent,
      };

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final days = widget.days;
    final values = days.map(_value).toList();
    final total = values.fold(0, (a, b) => a + b);
    final max = values.fold(0, (a, b) => b > a ? b : a);
    final sel = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_Metric>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final m in _Metric.values)
                ButtonSegment(value: m, label: Text(m.label, style: const TextStyle(fontSize: 12))),
            ],
            selected: {_metric},
            onSelectionChanged: (s) => setState(() {
              _metric = s.first;
              _selected = null;
            }),
          ),
        ),
        const SizedBox(height: 16),
        // Headline: the total, or the tapped day.
        Text(
          sel == null ? '$total' : '${values[sel]}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        Text(
          sel == null ? '${_metric.label.toLowerCase()} in 14 days' : _date(days[sel].day),
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: max == 0
              ? Center(child: Text('No activity yet', style: TextStyle(color: muted)))
              : LayoutBuilder(
                  builder: (context, box) {
                    final slot = box.maxWidth / days.length;
                    final barW = (slot * 0.55).clamp(4.0, 18.0);
                    return Stack(
                      children: [
                        // Recessive baseline + top gridline with its value.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(height: 1, color: cs.outlineVariant),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: Row(children: [
                            Expanded(
                                child: Container(
                                    height: 1, color: cs.outlineVariant.withValues(alpha: 0.5))),
                            const SizedBox(width: 4),
                            Text('$max', style: TextStyle(fontSize: 10, color: muted)),
                          ]),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < days.length; i++)
                              // Whole column is the hit target, wider than the bar.
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _selected = _selected == i ? null : i),
                                child: SizedBox(
                                  width: slot,
                                  height: box.maxHeight,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      width: barW,
                                      height: values[i] == 0
                                          ? 0
                                          : (values[i] / max * (box.maxHeight - 16)).clamp(2.0, box.maxHeight),
                                      decoration: BoxDecoration(
                                        color: sel == null || sel == i
                                            ? _metric.color
                                            : _metric.color.withValues(alpha: 0.35),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),
        const SizedBox(height: 6),
        if (days.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_date(days.first.day), style: TextStyle(fontSize: 11, color: muted)),
              Text('Today', style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
      ],
    );
  }
}
