/// In-memory fakes for every feature that has no backend yet. Sample data
/// is fictional. Each fake accepts a [latency] so widget tests can set it
/// to zero.
library;

import 'package:flutter/material.dart';

import '../../features/doctor/data/doctor_repository.dart';
import '../../features/home/data/insights_repository.dart';
import '../../features/meds/data/meds_repository.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/reports/data/report_models.dart';
import '../../features/reports/data/reports_repository.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/share/data/share_repository.dart';
import '../../features/wellness/data/wellness_repository.dart';
import 'fake_reports_repository.dart';

export 'fake_reports_repository.dart';

class FakeMedsRepository implements MedsRepository {
  FakeMedsRepository({
    this.latency = const Duration(milliseconds: 250),
    List<String> seed = const <String>[],
  }) {
    for (final name in seed) {
      _items.add(Medicine(id: _nextId++, name: name));
    }
  }

  final Duration latency;
  final List<Medicine> _items = <Medicine>[];
  int _nextId = 1;

  static const List<String> catalogue = <String>[
    'Metformin 500 mg',
    'Ibuprofen 400 mg',
    'Warfarin 5 mg',
    'Paracetamol 500 mg',
    'Amlodipine 5 mg',
    'Atorvastatin 20 mg',
  ];

  @override
  Future<List<Medicine>> list() async {
    await Future<void>.delayed(latency);
    return List<Medicine>.unmodifiable(_items);
  }

  @override
  Future<List<String>> suggestions() async {
    await Future<void>.delayed(latency);
    final Set<String> have = _items.map((m) => m.name).toSet();
    return catalogue.where((n) => !have.contains(n)).toList();
  }

  @override
  Future<Medicine> add(String name) async {
    await Future<void>.delayed(latency);
    final Medicine m = Medicine(id: _nextId++, name: name.trim());
    _items.add(m);
    return m;
  }

  @override
  Future<void> remove(int id) async {
    await Future<void>.delayed(latency);
    _items.removeWhere((m) => m.id == id);
  }

  @override
  Future<List<InteractionWarning>> checkInteractions() async {
    await Future<void>.delayed(latency * 2);
    final Set<String> names = _items
        .map((m) => m.name.toLowerCase().split(' ').first)
        .toSet();
    final List<InteractionWarning> warnings = <InteractionWarning>[];
    if (names.contains('ibuprofen') && names.contains('warfarin')) {
      warnings.add(
        const InteractionWarning(
          title: 'Ibuprofen with warfarin',
          body:
              'Together they raise the risk of serious bleeding. Don’t take '
              'both unless your doctor agrees.',
        ),
      );
    }
    if (names.contains('metformin') && names.contains('ibuprofen')) {
      warnings.add(
        const InteractionWarning(
          title: 'Ibuprofen with metformin',
          body:
              'Long courses of ibuprofen can strain the kidneys, which also '
              'clear metformin. Short use is usually fine; ask if it is more '
              'than a few days.',
        ),
      );
    }
    return warnings;
  }

  @override
  Future<ScanResult> scanPacket() async {
    await Future<void>.delayed(latency * 4);
    return const ScanResult(
      readName: 'Panadol 500 mg',
      genericName: 'Paracetamol 500 mg',
      safeWithCurrent: true,
      note: 'Safe with your current medicines.',
    );
  }
}

class FakeWellnessRepository implements WellnessRepository {
  FakeWellnessRepository({
    this.latency = const Duration(milliseconds: 200),
    WellnessDay? seed,
  }) : _day =
           seed ??
           const WellnessDay(
             waterMl: 750,
             waterGoalMl: 2400,
             steps: 4120,
             stepGoal: 6000,
             exerciseLabel: null,
             stepGoalNote: 'goal set for your condition',
           );

  final Duration latency;
  WellnessDay _day;

  @override
  Future<WellnessDay> today() async {
    await Future<void>.delayed(latency);
    return _day;
  }

  @override
  Future<WellnessDay> addWater(int ml) async {
    await Future<void>.delayed(latency);
    final int next = _day.waterMl + ml;
    _day = _day.copyWith(waterMl: next);
    return _day;
  }

  @override
  Future<WellnessDay> addSteps(int steps) async {
    await Future<void>.delayed(latency);
    _day = _day.copyWith(steps: _day.steps + steps);
    return _day;
  }

  @override
  Future<WellnessDay> logExercise(String label, {int minutes = 10}) async {
    await Future<void>.delayed(latency);
    _day = _day.copyWith(
      exerciseLabel: label,
      exerciseMinutes: _day.exerciseMinutes + minutes,
    );
    return _day;
  }

  @override
  Future<void> clearLocal() async {
    _day = const WellnessDay(
      waterMl: 0,
      waterGoalMl: 2400,
      steps: 0,
      stepGoal: 6000,
      exerciseLabel: null,
      stepGoalNote: 'general starting goal',
    );
  }
}

class FakeShareRepository implements ShareRepository {
  FakeShareRepository({
    this.latency = const Duration(milliseconds: 250),
    DateTime Function()? clock,
    this.patientName = 'Muhammad',
  }) : _now = clock ?? DateTime.now;

  final Duration latency;
  final DateTime Function() _now;
  final String patientName;
  ShareSession? _session;
  int _counter = 0;

  @override
  Future<ShareSession?> active() async {
    await Future<void>.delayed(latency);
    final s = _session;
    if (s != null && s.isExpired(_now())) _session = null;
    return _session;
  }

  @override
  Future<ShareSession> create({required int minutes}) async {
    await Future<void>.delayed(latency);
    final DateTime now = _now();
    _counter++;
    _session = ShareSession(
      code: 'MDX-${now.millisecondsSinceEpoch.toRadixString(36)}-$_counter',
      minutes: minutes,
      createdAt: now,
      expiresAt: now.add(Duration(minutes: minutes)),
    );
    return _session!;
  }

  @override
  Future<void> revoke() async {
    await Future<void>.delayed(latency);
    _session = null;
  }

  @override
  Future<DoctorPortalView> portalView(String code) async {
    await Future<void>.delayed(latency);
    final s = _session;
    final DateTime expires = s != null && s.code == code && !s.isExpired(_now())
        ? s.expiresAt
        : _now().add(const Duration(minutes: 28, seconds: 14));
    return DoctorPortalView(
      patientName: patientName,
      summary: 'Diabetes · Peanut allergy',
      records: const <SharedRecord>[
        SharedRecord(
          kind: SharedRecordKind.report,
          title: 'Blood test, 18 Oct',
        ),
        SharedRecord(
          kind: SharedRecordKind.medicines,
          title: 'Current medicines (3)',
        ),
      ],
      expiresAt: expires,
    );
  }
}

class FakeDoctorRepository implements DoctorRepository {
  FakeDoctorRepository({this.latency = const Duration(milliseconds: 200)});

  final Duration latency;

  static const Map<String, SpecialistMatch> _matches =
      <String, SpecialistMatch>{
        'Thirst and tiredness': SpecialistMatch(
          specialist: 'Endocrinologist',
          why:
              'Your HbA1c is rising and you mentioned thirst and tiredness. '
              'These often point to blood sugar changes.',
        ),
        'Chest pain': SpecialistMatch(
          specialist: 'Cardiologist',
          why:
              'Chest pain should be checked by a heart specialist first, '
              'even when it turns out to be muscular. If it is severe or '
              'sudden, go to emergency now.',
        ),
        'Skin rash': SpecialistMatch(
          specialist: 'Dermatologist',
          why:
              'A skin specialist can tell an allergy from an infection by '
              'looking, and you have a listed allergy.',
        ),
        'Joint pain': SpecialistMatch(
          specialist: 'Rheumatologist',
          why:
              'Pain in several joints, especially in the morning, is usually '
              'assessed by a joint and autoimmune specialist.',
        ),
      };

  @override
  Future<List<String>> symptoms() async {
    await Future<void>.delayed(latency);
    return _matches.keys.toList();
  }

  @override
  Future<SpecialistMatch> match(String symptom) async {
    await Future<void>.delayed(latency);
    return _matches[symptom] ??
        const SpecialistMatch(
          specialist: 'General physician',
          why:
              'A general physician can examine you and refer you to the '
              'right specialist.',
        );
  }
}

class FakeInsightsRepository implements InsightsRepository {
  FakeInsightsRepository({
    this.latency = const Duration(milliseconds: 200),
    this.insight = const Insight(
      title: 'Your HbA1c has risen across 3 reports',
      body: '5.9 in March to 6.4 now. Worth raising with your doctor.',
      marker: 'HbA1c',
    ),
    this.reportsCount = 4,
  });

  final Duration latency;
  final Insight? insight;

  /// Fewer than two reports means "not enough data" everywhere.
  final int reportsCount;

  bool get _needsReports => reportsCount < 2;

  @override
  Future<Insight?> homeInsight() async {
    await Future<void>.delayed(latency);
    return _needsReports ? null : insight;
  }

  @override
  Future<TrendSeries?> trend({String? marker}) async {
    await Future<void>.delayed(latency);
    if (_needsReports) return null;
    if (marker == null || marker.trim().isEmpty) return sampleTrends().first;
    final String key = marker.toLowerCase().replaceAll(' ', '');
    for (final TrendSeries s in sampleTrends()) {
      if (s.marker.toLowerCase().replaceAll(' ', '') == key) return s;
    }
    return null;
  }

  @override
  Future<TrendOverview> overview() async {
    await Future<void>.delayed(latency);
    if (_needsReports) {
      return TrendOverview(
        reportsCount: reportsCount,
        needsReports: true,
        insight: null,
        trends: const <MarkerTrend>[],
      );
    }
    final List<TrendSeries> series = sampleTrends();
    return TrendOverview(
      reportsCount: reportsCount,
      needsReports: false,
      insight: insight,
      trends: <MarkerTrend>[
        MarkerTrend(
          marker: series[0].marker,
          unit: series[0].unit,
          focus: true,
          direction: TrendDirection.rising,
          latestStatus: ValueStatus.warn,
          pointCount: series[0].points.length,
          series: series[0],
        ),
        MarkerTrend(
          marker: series[1].marker,
          unit: series[1].unit,
          focus: true,
          direction: TrendDirection.stable,
          latestStatus: ValueStatus.ok,
          pointCount: series[1].points.length,
          series: series[1],
        ),
        MarkerTrend(
          marker: series[2].marker,
          unit: series[2].unit,
          focus: false,
          direction: TrendDirection.falling,
          latestStatus: ValueStatus.ok,
          pointCount: series[2].points.length,
          series: series[2],
        ),
      ],
    );
  }

  /// Obviously-sample histories: HbA1c (alert), fasting glucose, LDL.
  static List<TrendSeries> sampleTrends() => <TrendSeries>[
    FakeReportsRepository.sampleTrend(),
    const TrendSeries(
      marker: 'Fasting glucose',
      unit: 'mg/dL',
      points: <TrendPoint>[
        TrendPoint(label: 'Mar', value: 92),
        TrendPoint(label: 'Jun', value: 95),
        TrendPoint(label: 'Aug', value: 94),
        TrendPoint(label: 'Oct', value: 96),
      ],
      threshold: 99,
      rangeLabel: '4 reports · Mar to Oct',
    ),
    const TrendSeries(
      marker: 'LDL',
      unit: 'mg/dL',
      points: <TrendPoint>[
        TrendPoint(label: 'Mar', value: 118),
        TrendPoint(label: 'Aug', value: 104),
        TrendPoint(label: 'Oct', value: 97),
      ],
      threshold: 100,
      rangeLabel: '3 reports · Mar to Oct',
    ),
  ];
}

/// In-memory `/profile`. Applies partial drafts the way the server does
/// (age from date of birth, consent stamped, `onboarding_complete` derived,
/// gender-filtered answers only kept for the group they apply to).
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.latency = const Duration(milliseconds: 200),
    PatientProfile? seed,
    DateTime Function()? clock,
  }) : _profile = seed ?? sampleProfile(),
       _now = clock ?? DateTime.now;

  final Duration latency;
  final DateTime Function() _now;
  PatientProfile _profile;

  /// Obviously fictional sample patient.
  static PatientProfile sampleProfile() => PatientProfile(
    id: 1,
    name: 'Sample Patient',
    email: 'sample@example.com',
    dateOfBirth: DateTime(1998, 5, 14),
    age: 28,
    sexAtBirth: 'male',
    consent: const ProfileConsent(
      terms: true,
      healthData: true,
      version: kConsentVersion,
      acceptedAt: null,
    ),
    conditions: 'Diabetes',
    allergies: 'Peanuts',
    takesMedicines: true,
    medications: 'Metformin 500 mg',
    firstGoal: 'reports',
    heightCm: 172,
    weightKg: 68,
    onboardingComplete: true,
  );

  /// Calls to [save], newest last; tests assert on the partial bodies.
  final List<Map<String, dynamic>> savedBodies = <Map<String, dynamic>>[];
  int deleteCalls = 0;

  PatientProfile get current => _profile;

  @override
  Future<PatientProfile> fetch() async {
    await Future<void>.delayed(latency);
    return _profile;
  }

  @override
  Future<PatientProfile> save(ProfileDraft d) async {
    await Future<void>.delayed(latency);
    final String? name = d.name;
    if (name != null && (name.trim().length < 2 || name.trim().length > 60)) {
      throw const RepositoryException(
        'Use a name between 2 and 60 characters.',
        canRetry: false,
      );
    }
    final DateTime? dob = d.dateOfBirth;
    if (dob != null && PatientProfile.ageAt(dob, today: _now()) < 18) {
      throw const RepositoryException(
        'MedAIx is for adults. A parent or guardian can use it for you.',
        canRetry: false,
      );
    }
    savedBodies.add(d.toJson());
    _profile = _profile.apply(d, now: _now());
    return _profile;
  }

  @override
  Future<void> delete() async {
    await Future<void>.delayed(latency);
    deleteCalls++;
    _profile = _profile.cleared();
  }
}

class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    this.themeMode = ThemeMode.system,
    this.reminders = const ReminderSettings(),
    this.onboardingSeen = false,
  });

  ThemeMode themeMode;
  ReminderSettings reminders;
  bool onboardingSeen;

  @override
  Future<ThemeMode> loadThemeMode() async => themeMode;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async => themeMode = mode;

  @override
  Future<ReminderSettings> loadReminders() async => reminders;

  @override
  Future<void> saveReminders(ReminderSettings settings) async =>
      reminders = settings;

  @override
  Future<bool> loadOnboardingSeen() async => onboardingSeen;

  @override
  Future<void> saveOnboardingSeen(bool seen) async => onboardingSeen = seen;
}

/// A reports repository that always fails, for error-state demos/tests.
class FailingReportsRepository implements ReportsRepository {
  const FailingReportsRepository([
    this.message = 'Could not reach the MedAIx service.',
  ]);

  final String message;

  @override
  Future<List<LabReport>> listReports() async =>
      throw RepositoryException(message);

  @override
  Future<LabReport> getReport(int id) async =>
      throw RepositoryException(message);

  @override
  Future<LabReport> uploadReport(
    String filePath, {
    ReportLanguage language = ReportLanguage.english,
    void Function(UploadPhase phase)? onPhase,
  }) async => throw RepositoryException(message);
}
