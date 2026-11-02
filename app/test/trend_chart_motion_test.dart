import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahasync_medaix/features/reports/data/report_models.dart';
import 'package:tahasync_medaix/features/reports/ui/trend_chart.dart';
import 'package:tahasync_medaix/theme/app_theme.dart';

void main() {
  testWidgets('trend chart keeps endpoint labels readable on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 829);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: SizedBox(
              height: trendChartHeight,
              child: TrendChart(
                series: TrendSeries(
                  marker: 'Hemoglobin',
                  unit: 'g/dL',
                  points: <TrendPoint>[
                    TrendPoint(
                      date: DateTime(2026, 11, 1),
                      dateSource: 'report',
                      value: 10.5,
                    ),
                  ],
                  low: 11.5,
                  high: 16,
                  rangeLabel: '1 report',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder top = find.text('17.38');
    final Finder bottom = find.text('9.125');
    expect(top, findsOneWidget);
    expect(bottom, findsOneWidget);
    expect(find.text('16.5'), findsNothing);
    expect(tester.getRect(top).overlaps(tester.getRect(bottom)), isFalse);
    expect(tester.takeException(), isNull);
  });

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
