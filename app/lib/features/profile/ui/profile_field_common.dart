/// Shared controls used by profile, sign-up and onboarding screens.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
