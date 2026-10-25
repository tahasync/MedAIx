/// The questionnaire's controls, shared by sign-up (Screen 1), onboarding
/// (Screens 1–3) and Settings › Profile so every answer is captured the
/// same way. All values are wire values; labels come from `profile_form`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../providers/profile_form.dart';

/// Question heading with optional helper copy beneath.
class QuestionTitle extends StatelessWidget {
  const QuestionTitle(this.text, {super.key, this.helper, this.first = false});

  final String text;
  final String? helper;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(text, first: first),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sectionBottom),
            child: Text(
              helper!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: c.muted),
            ),
          ),
      ],
    );
  }
}

/// Small error line under a non-text control (chips, the date field).
class FieldError extends StatelessWidget {
  const FieldError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                LucideIcons.triangleAlert,
                size: AppSize.iconTiny,
                color: c.error,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick one of [options] (wire value in, wire value out).
class SingleChoiceChips extends StatelessWidget {
  const SingleChoiceChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final List<Option> options;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.chipGap,
      runSpacing: AppSpace.chipGap,
      children: [
        for (final Option option in options)
          AppChip(
            label: option.label,
            selected: value == option.value,
            onTap: enabled ? () => onChanged(option.value) : null,
          ),
      ],
    );
  }
}

/// Pick any of [options]; "None" and "Prefer not to say" stand alone.
class MultiChoiceChips extends StatelessWidget {
  const MultiChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.chipGap,
      runSpacing: AppSpace.chipGap,
      children: [
        for (final String option in options)
          AppChip(
            label: option,
            selected: selected.contains(option),
            onTap: enabled
                ? () => onChanged(toggleExclusive(selected, option))
                : null,
          ),
      ],
    );
  }
}

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
      builder: (context, child) => _themed(context, child),
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
    } catch (_) {
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

/// 2.3 — regular medicines: Yes / No, then names when Yes.
class MedicinesQuestion extends StatefulWidget {
  const MedicinesQuestion({
    super.key,
    required this.takesMedicines,
    required this.names,
    required this.onTakesMedicinesChanged,
    required this.onNamesChanged,
    this.enabled = true,
    this.fieldKey,
  });

  final bool? takesMedicines;
  final String names;
  final ValueChanged<bool> onTakesMedicinesChanged;
  final ValueChanged<String> onNamesChanged;
  final bool enabled;
  final Key? fieldKey;

  @override
  State<MedicinesQuestion> createState() => _MedicinesQuestionState();
}

class _MedicinesQuestionState extends State<MedicinesQuestion> {
  late final TextEditingController _names = TextEditingController(
    text: widget.names,
  );

  @override
  void didUpdateWidget(MedicinesQuestion old) {
    super.didUpdateWidget(old);
    if (widget.names != old.names && widget.names != _names.text) {
      _names.text = widget.names;
    }
  }

  @override
  void dispose() {
    _names.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QuestionTitle('Do you take any medicines regularly?'),
        Wrap(
          spacing: AppSpace.chipGap,
          runSpacing: AppSpace.chipGap,
          children: [
            AppChip(
              label: 'Yes',
              selected: widget.takesMedicines == true,
              onTap: widget.enabled
                  ? () => widget.onTakesMedicinesChanged(true)
                  : null,
            ),
            AppChip(
              label: 'No',
              selected: widget.takesMedicines == false,
              onTap: widget.enabled
                  ? () => widget.onTakesMedicinesChanged(false)
                  : null,
            ),
          ],
        ),
        if (widget.takesMedicines == true) ...[
          const SizedBox(height: AppSpace.lg),
          TextField(
            key: widget.fieldKey,
            controller: _names,
            enabled: widget.enabled,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            minLines: 2,
            maxLines: 4,
            onChanged: widget.onNamesChanged,
            decoration: const InputDecoration(
              labelText: 'Medicine names',
              hintText: 'One per line, or separated by commas',
              helperText: 'Names only, no doses needed now.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Scanning the packet to add medicines is coming in a later '
            'update.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: c.muted),
          ),
        ],
      ],
    );
  }
}

/// 2.4F / 2.4M — the one extra question for the group it applies to.
/// Renders nothing for everyone else.
class GenderFilterQuestion extends StatelessWidget {
  const GenderFilterQuestion({
    super.key,
    required this.sexAtBirth,
    required this.age,
    required this.pregnancyStatus,
    required this.prostateUrinaryIssue,
    required this.onPregnancyChanged,
    required this.onProstateChanged,
    this.enabled = true,
  });

  final String? sexAtBirth;
  final int? age;
  final String? pregnancyStatus;
  final String? prostateUrinaryIssue;
  final ValueChanged<String> onPregnancyChanged;
  final ValueChanged<String> onProstateChanged;
  final bool enabled;

  static bool asksPregnancy(String? sex) => sex == 'female';
  static bool asksProstate(String? sex, int? age) =>
      sex == 'male' && (age ?? 0) >= 40;

  @override
  Widget build(BuildContext context) {
    if (asksPregnancy(sexAtBirth)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuestionTitle(
            'Are you pregnant or breastfeeding?',
            helper: 'Changes medicine safety and lab ranges.',
          ),
          SingleChoiceChips(
            options: kPregnancyOptions,
            value: pregnancyStatus,
            onChanged: onPregnancyChanged,
            enabled: enabled,
          ),
        ],
      );
    }
    if (asksProstate(sexAtBirth, age)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const QuestionTitle(
            'Any prostate or urinary problems?',
            helper: 'Linked to diabetes and medicine choices.',
          ),
          SingleChoiceChips(
            options: kProstateOptions,
            value: prostateUrinaryIssue,
            onChanged: onProstateChanged,
            enabled: enabled,
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

/// 3.1 — one goal, as full-width rows so long labels never truncate.
class GoalChoice extends StatelessWidget {
  const GoalChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.card),
      child: ListRows(
        rows: [
          for (final Option option in kGoalOptions)
            ListRow(
              title: option.label,
              semanticLabel: option.label,
              trailing: value == option.value
                  ? ExcludeSemantics(
                      child: Icon(
                        LucideIcons.check,
                        size: AppSize.icon,
                        color: c.text,
                      ),
                    )
                  : const SizedBox(width: AppSize.icon, height: AppSize.icon),
              onTap: enabled ? () => onChanged(option.value) : null,
            ),
        ],
      ),
    );
  }
}

/// Metric / imperial toggle for 3.2.
class UnitToggle extends StatelessWidget {
  const UnitToggle({
    super.key,
    required this.unit,
    required this.onChanged,
    this.enabled = true,
  });

  final UnitSystem unit;
  final ValueChanged<UnitSystem> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.chipGap,
      runSpacing: AppSpace.chipGap,
      children: [
        AppChip(
          label: 'cm / kg',
          selected: unit == UnitSystem.metric,
          onTap: enabled ? () => onChanged(UnitSystem.metric) : null,
        ),
        AppChip(
          label: 'ft / lb',
          selected: unit == UnitSystem.imperial,
          onTap: enabled ? () => onChanged(UnitSystem.imperial) : null,
        ),
      ],
    );
  }
}

/// 3.2 — height and weight. Values in and out are always cm / kg; the
/// fields convert on the unit toggle and round sensibly (whole cm, one
/// decimal kg, whole inches and pounds).
class HeightWeightFields extends StatefulWidget {
  const HeightWeightFields({
    super.key,
    required this.heightCm,
    required this.weightKg,
    required this.unit,
    required this.onHeightChanged,
    required this.onWeightChanged,
    this.heightError,
    this.weightError,
    this.enabled = true,
    this.heightKey,
    this.weightKey,
  });

  final double? heightCm;
  final double? weightKg;
  final UnitSystem unit;

  /// Null when cleared; NaN when the text is not a number.
  final ValueChanged<double?> onHeightChanged;
  final ValueChanged<double?> onWeightChanged;
  final String? heightError;
  final String? weightError;
  final bool enabled;
  final Key? heightKey;
  final Key? weightKey;

  @override
  State<HeightWeightFields> createState() => _HeightWeightFieldsState();
}

class _HeightWeightFieldsState extends State<HeightWeightFields> {
  final TextEditingController _height = TextEditingController();
  final TextEditingController _feet = TextEditingController();
  final TextEditingController _inches = TextEditingController();
  final TextEditingController _weight = TextEditingController();

  @override
  void initState() {
    super.initState();
    _writeFromValues();
  }

  @override
  void didUpdateWidget(HeightWeightFields old) {
    super.didUpdateWidget(old);
    if (widget.unit != old.unit) _writeFromValues();
  }

  @override
  void dispose() {
    _height.dispose();
    _feet.dispose();
    _inches.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Fills the fields from the canonical cm / kg values for the current
  /// unit; only called when the unit flips, so typing is never overwritten.
  void _writeFromValues() {
    final double? h = widget.heightCm;
    final double? w = widget.weightKg;
    final bool hOk = h != null && !h.isNaN;
    final bool wOk = w != null && !w.isNaN;
    if (widget.unit == UnitSystem.metric) {
      _height.text = hOk ? ProfileValidation.formatNumber(h) : '';
      _weight.text = wOk ? ProfileValidation.formatNumber(w) : '';
    } else {
      if (hOk) {
        final (:int feet, :int inches) = Units.cmToFeetInches(h);
        _feet.text = feet.toString();
        _inches.text = inches.toString();
      } else {
        _feet.text = '';
        _inches.text = '';
      }
      _weight.text = wOk ? Units.kgToLb(w).toString() : '';
    }
  }

  void _heightMetricChanged(String raw) =>
      widget.onHeightChanged(parseNumber(raw));

  void _heightImperialChanged() {
    final String ft = _feet.text.trim();
    final String inch = _inches.text.trim();
    if (ft.isEmpty && inch.isEmpty) {
      widget.onHeightChanged(null);
      return;
    }
    final int? feet = ft.isEmpty ? 0 : int.tryParse(ft);
    final int? inches = inch.isEmpty ? 0 : int.tryParse(inch);
    if (feet == null || inches == null) {
      widget.onHeightChanged(double.nan);
      return;
    }
    widget.onHeightChanged(Units.feetInchesToCm(feet, inches));
  }

  void _weightChanged(String raw) {
    final double? value = parseNumber(raw);
    if (value == null || value.isNaN || widget.unit == UnitSystem.metric) {
      widget.onWeightChanged(value);
      return;
    }
    widget.onWeightChanged(Units.lbToKg(value));
  }

  @override
  Widget build(BuildContext context) {
    const TextInputType decimal = TextInputType.numberWithOptions(
      decimal: true,
    );
    final bool metric = widget.unit == UnitSystem.metric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metric)
          TextField(
            key: widget.heightKey,
            controller: _height,
            enabled: widget.enabled,
            keyboardType: decimal,
            textInputAction: TextInputAction.next,
            onChanged: _heightMetricChanged,
            decoration: InputDecoration(
              labelText: 'Height',
              suffixText: 'cm',
              errorText: widget.heightError,
              errorMaxLines: 3,
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: widget.heightKey,
                  controller: _feet,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _heightImperialChanged(),
                  decoration: InputDecoration(
                    labelText: 'Height',
                    suffixText: 'ft',
                    errorText: widget.heightError,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: TextField(
                  controller: _inches,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _heightImperialChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Inches',
                    suffixText: 'in',
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          key: widget.weightKey,
          controller: _weight,
          enabled: widget.enabled,
          keyboardType: decimal,
          textInputAction: TextInputAction.done,
          onChanged: _weightChanged,
          decoration: InputDecoration(
            labelText: 'Weight',
            suffixText: metric ? 'kg' : 'lb',
            errorText: widget.weightError,
            errorMaxLines: 3,
          ),
        ),
      ],
    );
  }
}
