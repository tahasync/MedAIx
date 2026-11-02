import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/features/reports/data/report_models.dart';
import 'package:tahasync_medaix/features/reports/ui/trend_chart.dart';
import 'package:tahasync_medaix/theme/app_theme.dart';

void main() {
  testWidgets('trend chart has no running animation with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TrendChart(
              series: TrendSeries(
                marker: 'Hemoglobin',
                unit: 'g/dL',
                points: <TrendPoint>[
                  TrendPoint(
                    date: DateTime(2026, 9, 1),
                    dateSource: 'report',
                    value: 11,
                  ),
                  TrendPoint(
                    date: DateTime(2026, 10, 1),
                    dateSource: 'report',
                    value: 12,
                  ),
                ],
                low: 11.5,
                high: 16,
                rangeLabel: '2 readings',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TrendChart), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
