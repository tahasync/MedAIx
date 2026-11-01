import '../../../core/widgets/chips_and_status.dart';

String severityKey(String value) {
  final String key = value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
  return switch (key) {
    'normal' || 'in_range' => 'normal',
    'slightly_low' => 'slightly_low',
    'slightly_high' => 'slightly_high',
    'low' || 'very_low' => 'low',
    'high' || 'very_high' || 'out_of_range' => 'high',
    'critical' => 'critical',
    _ => 'unknown',
  };
}

ValueStatus severityStatus(String value) => switch (severityKey(value)) {
  'normal' => ValueStatus.ok,
  'slightly_low' || 'slightly_high' => ValueStatus.warn,
  'low' || 'high' || 'critical' => ValueStatus.error,
  _ => ValueStatus.neutral,
};

String severityLabel(String value) => switch (severityKey(value)) {
  'normal' => 'Normal',
  'slightly_low' => 'Slightly low',
  'slightly_high' => 'Slightly high',
  'low' => 'Low',
  'high' => 'High',
  'critical' => 'Critical',
  _ => 'Unrated',
};
