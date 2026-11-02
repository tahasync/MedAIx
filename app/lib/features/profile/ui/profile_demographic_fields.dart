/// Shared controls used by profile, sign-up and onboarding screens.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal/legal_constants.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../providers/profile_form.dart';
import 'profile_field_common.dart';

/// 1.4 — a tappable field that opens the date picker (typed entry first,
/// since a birth date is quicker to type than to scroll to).
class DateOfBirthField extends StatelessWidget {
  const DateOfBirthField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
    this.label = 'Date of birth',
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  final String? errorText;
  final String label;

  Future<void> _pick(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(ProfileValidation.minYear),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.input,
      helpText: 'Date of birth',
      fieldLabelText: 'Date of birth',
      fieldHintText: 'mm/dd/yyyy',
      errorFormatText: 'Enter the date as mm/dd/yyyy.',
      errorInvalidText: 'Choose a date between 1900 and today.',
      confirmText: 'Done',
      cancelText: 'Cancel',
      builder: _themed,
    );
    if (picked != null) onChanged(picked);
  }

  /// Flat dialog on the app tokens: `surface` plate, card radius, no tint.
  static Widget _themed(BuildContext context, Widget? child) {
    final c = context.colors;
    final ThemeData theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        datePickerTheme: DatePickerThemeData(
          backgroundColor: c.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
          headerBackgroundColor: c.surface2,
          headerForegroundColor: c.text,
          dayForegroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.onPrimary : c.text,
          ),
          dayBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? c.primary
                : Colors.transparent,
          ),
          todayForegroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.onPrimary : c.text,
          ),
          todayBorder: BorderSide(color: c.primary),
          yearForegroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.onPrimary : c.text,
          ),
          yearBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? c.primary
                : Colors.transparent,
          ),
          dividerColor: c.hairline,
          inputDecorationTheme: theme.inputDecorationTheme,
          cancelButtonStyle: TextButton.styleFrom(foregroundColor: c.text),
          confirmButtonStyle: TextButton.styleFrom(foregroundColor: c.text),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String display = value == null ? '' : formatLongDate(value!);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: value == null ? 'Not set' : display,
      hint: 'Opens a date picker',
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        borderRadius: AppRadius.inputAll,
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            errorMaxLines: 3,
            enabled: enabled,
            prefixIcon: const Icon(LucideIcons.calendar),
            suffixIcon: Icon(LucideIcons.chevronDown, color: c.muted),
          ),
          child: Text(display, style: text.bodyMedium),
        ),
      ),
    );
  }
}

/// 1.5 — sex at birth with the spec's helper line.
class SexAtBirthField extends StatelessWidget {
  const SexAtBirthField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
    this.title = 'What was your sex at birth?',
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? errorText;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QuestionTitle(title, helper: kSexHelper),
        SingleChoiceChips(
          options: kSexOptions,
          value: value,
          onChanged: onChanged,
          enabled: enabled,
        ),
        if (errorText != null) FieldError(message: errorText!),
      ],
    );
  }
}

/// 1.6 and 1.7 — two switches, never pre-ticked, with links to the
/// policies.
class ConsentSwitches extends StatelessWidget {
  const ConsentSwitches({
    super.key,
    required this.terms,
    required this.healthData,
    required this.onTermsChanged,
    required this.onHealthDataChanged,
    this.enabled = true,
  });

  final bool terms;
  final bool healthData;
  final ValueChanged<bool> onTermsChanged;
  final ValueChanged<bool> onHealthDataChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConsentRow(
          text: kTermsConsentText,
          value: terms,
          onChanged: enabled ? onTermsChanged : null,
          label: 'Agree to the Terms and Privacy Policy',
        ),
        Wrap(
          children: [
            LinkButton(
              label: 'Terms',
              onPressed: () => _open(context, kTermsUrl),
            ),
            LinkButton(
              label: 'Privacy Policy',
              onPressed: () => _open(context, kPrivacyUrl),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        _ConsentRow(
          text: kHealthConsentText,
          value: healthData,
          onChanged: enabled ? onHealthDataChanged : null,
          label: 'Agree to health data processing',
        ),
      ],
    );
  }

  static Future<void> _open(BuildContext context, String url) async {
    bool opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Object catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      showToast(context, 'Couldn’t open the page. Try again later.');
    }
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.text,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final String text;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: AppSpace.lg),
          AppSwitch(value: value, onChanged: onChanged, label: label),
        ],
      ),
    );
  }
}
