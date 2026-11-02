/// Profile widgets split into read and edit responsibilities.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../../reports/data/reports_repository.dart';
import '../data/profile_repository.dart';
import '../providers/profile_form.dart';
import '../providers/profile_providers.dart';
import 'profile_fields.dart';

/// Edits and saves profile details as a partial update.
class ProfileEditForm extends ConsumerStatefulWidget {
  const ProfileEditForm({
    super.key,
    required this.profile,
    required this.email,
    required this.onSaved,
    required this.onCancel,
  });

  final PatientProfile profile;
  final String? email;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  ConsumerState<ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends ConsumerState<ProfileEditForm> {
  late final TextEditingController _name;
  DateTime? _dateOfBirth;
  String? _dateOfBirthError;
  String? _sexAtBirth;
  String? _sexError;
  bool _terms = false;
  bool _healthData = false;
  String? _consentError;
  late Set<String> _conditions;
  late Set<String> _allergies;
  bool? _takesMedicines;
  late String _medicines;
  String? _pregnancyStatus;
  String? _prostateUrinaryIssue;
  String? _firstGoal;
  double? _heightCm;
  double? _weightKg;
  UnitSystem _unit = UnitSystem.metric;
  bool _validateNumbers = false;
  String? _saveError;

  PatientProfile get _p => widget.profile;

  /// Consent is on file: show it read-only. Otherwise (after "Delete my
  /// health data") offer the two switches again.
  bool get _needsConsent => !(_p.consent?.complete ?? false);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _p.name ?? '');
    _dateOfBirth = _p.dateOfBirth;
    _sexAtBirth = _p.sexAtBirth;
    _conditions = _p.conditionList.toSet();
    _allergies = _p.allergyList.toSet();
    _takesMedicines = _p.takesMedicines;
    _medicines = _p.medicationList.join('\n');
    _pregnancyStatus = _p.pregnancyStatus;
    _prostateUrinaryIssue = _p.prostateUrinaryIssue;
    _firstGoal = _p.firstGoal;
    _heightCm = _p.heightCm;
    _weightKg = _p.weightKg;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  int? get _age =>
      _dateOfBirth == null ? _p.age : PatientProfile.ageAt(_dateOfBirth!);

  void _setDateOfBirth(DateTime value) {
    final DateTime date = DateTime(value.year, value.month, value.day);
    final String? error = ProfileValidation.dateOfBirth(date);
    setState(() {
      if (error != null) {
        _dateOfBirthError = error;
      } else {
        _dateOfBirth = date;
        _dateOfBirthError = null;
      }
    });
  }

  void _setSex(String value) => setState(() {
    _sexAtBirth = value;
    _sexError = null;
    if (value != 'female') _pregnancyStatus = null;
    if (value != 'male') _prostateUrinaryIssue = null;
  });

  /// Only what changed, so an untouched field is never overwritten.
  ProfileDraft _draft() {
    final String name = _name.text.trim();
    final String conditions = PatientProfile.join(_conditions);
    final String allergies = PatientProfile.join(_allergies);
    final String medications = _takesMedicines == true
        ? PatientProfile.join(splitNames(_medicines))
        : '';
    String? changed(String? next, String? current) =>
        (next ?? '') == (current ?? '') ? null : next;
    double? changedNumber(double? next, double? current) =>
        next == null || next.isNaN || next == current ? null : next;
    return ProfileDraft(
      name: changed(name, _p.name),
      dateOfBirth: _dateOfBirth == _p.dateOfBirth ? null : _dateOfBirth,
      sexAtBirth: changed(_sexAtBirth, _p.sexAtBirth),
      grantConsent: _needsConsent && _terms && _healthData,
      conditions: changed(conditions, PatientProfile.join(_p.conditionList)),
      allergies: changed(allergies, PatientProfile.join(_p.allergyList)),
      takesMedicines: _takesMedicines == _p.takesMedicines
          ? null
          : _takesMedicines,
      medications: _takesMedicines == null
          ? null
          : changed(medications, PatientProfile.join(_p.medicationList)),
      pregnancyStatus: changed(_pregnancyStatus, _p.pregnancyStatus),
      prostateUrinaryIssue: changed(
        _prostateUrinaryIssue,
        _p.prostateUrinaryIssue,
      ),
      firstGoal: changed(_firstGoal, _p.firstGoal),
      heightCm: changedNumber(_heightCm, _p.heightCm),
      weightKg: changedNumber(_weightKg, _p.weightKg),
    );
  }

  Future<void> _save() async {
    final String? nameError = ProfileValidation.name(_name.text);
    final String? sexError = _sexAtBirth == null && _p.sexAtBirth != null
        ? ProfileValidation.sex(_sexAtBirth)
        : null;
    final String? consentError = _needsConsent && (_terms != _healthData)
        ? 'Turn on both switches to give consent, or leave both off.'
        : null;
    final bool numbersOk =
        ProfileValidation.heightCm(_heightCm) == null &&
        ProfileValidation.weightKg(_weightKg) == null;
    setState(() {
      _validateNumbers = true;
      _sexError = sexError;
      _consentError = consentError;
      _saveError = null;
    });
    if (nameError != null ||
        sexError != null ||
        consentError != null ||
        _dateOfBirthError != null ||
        !numbersOk) {
      return;
    }

    final ProfileDraft draft = _draft();
    if (draft.isEmpty) {
      widget.onCancel();
      return;
    }
    final PatientProfile? saved = await ref
        .read(profileEditorProvider.notifier)
        .save(draft);
    if (!mounted) return;
    if (saved != null) {
      widget.onSaved();
      return;
    }
    final Object? error = ref.read(profileEditorProvider).error;
    setState(() {
      _saveError = error is RepositoryException
          ? error.message
          : 'Could not save your details.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool saving = ref.watch(profileEditorProvider).isLoading;
    final bool enabled = !saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Account', first: true),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('profile-name'),
                controller: _name,
                enabled: enabled,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: ProfileValidation.name,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                key: const Key('profile-email'),
                initialValue: widget.email ?? '',
                enabled: false,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  helperText: 'Your email can’t be changed here.',
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              DateOfBirthField(
                key: const Key('profile-dob'),
                value: _dateOfBirth,
                enabled: enabled,
                errorText: _dateOfBirthError,
                onChanged: _setDateOfBirth,
              ),
              SexAtBirthField(
                title: 'Sex at birth',
                value: _sexAtBirth,
                enabled: enabled,
                errorText: _sexError,
                onChanged: _setSex,
              ),
            ],
          ),
        ),
        const SectionTitle('Health basics'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const QuestionTitle('Ongoing conditions', first: true),
              MultiChoiceChips(
                options: kConditionOptions,
                selected: _conditions,
                enabled: enabled,
                onChanged: (v) => setState(() => _conditions = v),
              ),
              const QuestionTitle('Allergies'),
              MultiChoiceChips(
                options: kAllergyOptions,
                selected: _allergies,
                enabled: enabled,
                onChanged: (v) => setState(() => _allergies = v),
              ),
              MedicinesQuestion(
                fieldKey: const Key('profile-medicines'),
                takesMedicines: _takesMedicines,
                names: _medicines,
                enabled: enabled,
                onTakesMedicinesChanged: (v) =>
                    setState(() => _takesMedicines = v),
                onNamesChanged: (v) => _medicines = v,
              ),
              GenderFilterQuestion(
                sexAtBirth: _sexAtBirth,
                age: _age,
                pregnancyStatus: _pregnancyStatus,
                prostateUrinaryIssue: _prostateUrinaryIssue,
                enabled: enabled,
                onPregnancyChanged: (v) => setState(() => _pregnancyStatus = v),
                onProstateChanged: (v) =>
                    setState(() => _prostateUrinaryIssue = v),
              ),
            ],
          ),
        ),
        const SectionTitle('About you'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const QuestionTitle('First health goal', first: true),
              GoalChoice(
                value: _firstGoal,
                enabled: enabled,
                onChanged: (v) => setState(() => _firstGoal = v),
              ),
              const QuestionTitle('Height and weight'),
              UnitToggle(
                unit: _unit,
                enabled: enabled,
                onChanged: (v) => setState(() => _unit = v),
              ),
              const SizedBox(height: AppSpace.lg),
              HeightWeightFields(
                heightKey: const Key('profile-height'),
                weightKey: const Key('profile-weight'),
                heightCm: _heightCm,
                weightKg: _weightKg,
                unit: _unit,
                enabled: enabled,
                heightError: _validateNumbers
                    ? ProfileValidation.heightCm(_heightCm)
                    : null,
                weightError: _validateNumbers
                    ? ProfileValidation.weightKg(_weightKg)
                    : null,
                onHeightChanged: (v) => setState(() => _heightCm = v),
                onWeightChanged: (v) => setState(() => _weightKg = v),
              ),
            ],
          ),
        ),
        if (_needsConsent) ...[
          const SectionTitle('Consent'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'MedAIx needs your consent to process health answers. Turn '
                  'on both switches to give it again.',
                  style: text.bodySmall?.copyWith(color: c.muted),
                ),
                const SizedBox(height: AppSpace.lg),
                ConsentSwitches(
                  terms: _terms,
                  healthData: _healthData,
                  enabled: enabled,
                  onTermsChanged: (v) => setState(() {
                    _terms = v;
                    _consentError = null;
                  }),
                  onHealthDataChanged: (v) => setState(() {
                    _healthData = v;
                    _consentError = null;
                  }),
                ),
                if (_consentError != null) FieldError(message: _consentError!),
              ],
            ),
          ),
        ],
        if (_saveError != null) ...[
          const SizedBox(height: AppSpace.cardGap),
          ErrorCard(
            title: 'Couldn’t save your details',
            message: _saveError!,
            dataSafety: 'Your previous details are unchanged.',
            onPrimary: saving ? null : _save,
          ),
        ],
        const SizedBox(height: AppSpace.cardGap),
        PrimaryButton(label: 'Save details', loading: saving, onPressed: _save),
        const SizedBox(height: AppSpace.xs),
        LinkButton(label: 'Cancel', onPressed: saving ? null : widget.onCancel),
      ],
    );
  }
}
