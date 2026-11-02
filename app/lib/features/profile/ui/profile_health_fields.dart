/// Shared controls used by profile, sign-up and onboarding screens.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../providers/profile_form.dart';
import 'profile_field_common.dart';

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
