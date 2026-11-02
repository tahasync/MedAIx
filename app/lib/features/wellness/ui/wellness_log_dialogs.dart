/// Personal daily wellness log for water, steps and recorded movement.
library;

import 'package:flutter/material.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';

/// One tap of the water button, as in the mockup.
const int kWaterStepMl = 250;

/// Dialog widgets used to validate and return wellness log entries.
class MovementEntry {
  const MovementEntry({required this.activity, required this.minutes});

  final String activity;
  final int minutes;
}

class LogMovementDialog extends StatefulWidget {
  const LogMovementDialog({super.key});

  @override
  State<LogMovementDialog> createState() => _LogMovementDialogState();
}

class _LogMovementDialogState extends State<LogMovementDialog> {
  final TextEditingController _activity = TextEditingController(text: 'Walk');
  final TextEditingController _minutes = TextEditingController(text: '10');
  String? _activityError;
  String? _minutesError;

  @override
  void dispose() {
    _activity.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Log movement'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _activity,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Activity',
            hintText: 'Walk, stretching or cycling',
            errorText: _activityError,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _minutes,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Minutes',
            hintText: 'For example, 15',
            errorText: _minutesError,
          ),
        ),
      ],
    ),
    actions: [
      GhostButton(
        label: 'Cancel',
        compact: true,
        onPressed: () => Navigator.pop(context),
      ),
      PrimaryButton(
        label: 'Save activity',
        compact: true,
        onPressed: () {
          final String activity = _activity.text.trim();
          final int? minutes = int.tryParse(_minutes.text.trim());
          if (activity.isEmpty || activity.length > 40) {
            setState(
              () => _activityError =
                  'Enter an activity name up to 40 characters.',
            );
            return;
          }
          setState(() => _activityError = null);
          if (minutes == null || minutes < 1 || minutes > 480) {
            setState(
              () => _minutesError = 'Enter a duration from 1 to 480 minutes.',
            );
            return;
          }
          setState(() => _minutesError = null);
          Navigator.pop(
            context,
            MovementEntry(activity: activity, minutes: minutes),
          );
        },
      ),
    ],
  );
}

class LogStepsDialog extends StatefulWidget {
  const LogStepsDialog({super.key});

  @override
  State<LogStepsDialog> createState() => _LogStepsDialogState();
}

class _LogStepsDialogState extends State<LogStepsDialog> {
  final TextEditingController _input = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Log steps'),
    content: TextField(
      controller: _input,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Steps to add',
        hintText: 'For example, 1200',
        errorText: _validationError,
      ),
    ),
    actions: [
      GhostButton(
        label: 'Cancel',
        compact: true,
        onPressed: () => Navigator.pop(context),
      ),
      PrimaryButton(
        label: 'Log steps',
        compact: true,
        onPressed: () {
          final int? value = int.tryParse(_input.text.trim());
          if (value == null || value < 1 || value > 50000) {
            setState(
              () => _validationError = 'Enter a number from 1 to 50,000.',
            );
            return;
          }
          Navigator.pop(context, value);
        },
      ),
    ],
  );
}

/// Mockup habit card: icon tile, bold title, muted small subtitle, optional
/// trailing control, optional progress bar 12 px below.
