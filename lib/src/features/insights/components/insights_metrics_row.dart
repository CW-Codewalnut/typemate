import 'package:flutter/material.dart';

import '../../../core/insights_stats.dart';
import '../../../utils/text_metrics.dart';
import '../../../components/dashboard_cards.dart';

class InsightsMetricsRow extends StatelessWidget {
  const InsightsMetricsRow({super.key, required this.stats});

  final InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      DashboardMetricCard(
        value: stats.averageWordsPerMinute.toString(),
        label: 'Words per minute',
        child: _InsightGauge(percent: _topPercent(stats.averageWordsPerMinute)),
      ),
      DashboardMetricCard(
        value: stats.dictationCount.toString(),
        label: 'Dictation sessions',
        child: _DictationSessionSummary(stats: stats),
      ),
      DashboardMetricCard(
        value: formatCompactNumber(stats.totalWords),
        label: 'Total words dictated',
        child: _DeviceWordsSummary(stats: stats),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              for (final card in cards) ...[
                SizedBox(width: double.infinity, child: card),
                const SizedBox(height: 16),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 20),
            Expanded(child: cards[1]),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: cards[2]),
          ],
        );
      },
    );
  }

  int _topPercent(int wordsPerMinute) {
    if (wordsPerMinute >= 110) return 1;
    if (wordsPerMinute >= 80) return 5;
    if (wordsPerMinute >= 50) return 15;
    if (wordsPerMinute > 0) return 25;
    return 0;
  }
}

class _DictationSessionSummary extends StatelessWidget {
  const _DictationSessionSummary({required this.stats});

  final InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        _SummaryLine(
          value: formatCompactNumber(stats.averageWordsPerSession),
          label: 'avg words/session',
        ),
        const SizedBox(height: 8),
        _SummaryLine(
          value: stats.activeDays.toString(),
          label: stats.activeDays == 1 ? 'active day' : 'active days',
        ),
      ],
    );
  }
}

class _DeviceWordsSummary extends StatelessWidget {
  const _DeviceWordsSummary({required this.stats});

  final InsightsStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Divider(),
        Row(
          children: [
            const Icon(Icons.desktop_windows_outlined, size: 18),
            const SizedBox(width: 8),
            Text(
              'Desktop',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${formatCompactNumber(stats.todayWords)} today',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${formatCompactNumber(stats.totalWords)} words from local history',
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '$value $label',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _InsightGauge extends StatelessWidget {
  const _InsightGauge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SizedBox(
        width: 156,
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GaugePainter(color: theme.colorScheme.primary),
              ),
            ),
            Positioned(
              top: 36,
              child: Column(
                children: [
                  Text(
                    percent == 0 ? 'No pace yet' : 'Top',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    percent == 0 ? '0%' : '$percent%',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(16, 12, size.width - 32, size.height * 1.35);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 3.14, 3.14, false, paint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.color != color;
}
