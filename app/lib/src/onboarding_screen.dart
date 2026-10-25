/// Three-step profile questionnaire shown once after sign-in.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'providers.dart';
import 'theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _conditions = TextEditingController();
  final _medications = TextEditingController();
  final _allergies = TextEditingController();

  var _step = 0;
  var _sex = '';
  var _busy = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _weight.dispose();
    _height.dispose();
    _conditions.dispose();
    _medications.dispose();
    _allergies.dispose();
    super.dispose();
  }

  bool _validateStep() {
    String? message;
    if (_step == 0) {
      final age = int.tryParse(_age.text.trim());
      if (age == null || age < 1 || age > 120) {
        message = 'Enter an age from 1 to 120.';
      } else if (_sex.isEmpty) {
        message = 'Choose female, male, or other.';
      }
    } else if (_step == 1) {
      final weight = double.tryParse(_weight.text.trim());
      final height = double.tryParse(_height.text.trim());
      if (weight == null || weight <= 0 || weight > 500) {
        message = 'Enter a weight in kilograms, up to 500.';
      } else if (height == null || height <= 30 || height > 250) {
        message = 'Enter a height in centimetres, from 31 to 250.';
      }
    }
    setState(() => _message = message);
    return message == null;
  }

  Future<void> _finish() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .saveProfile(
            name: _name.text.trim(),
            age: int.parse(_age.text.trim()),
            weight: double.parse(_weight.text.trim()),
            height: double.parse(_height.text.trim()),
            sex: _sex,
            conditions: _conditions.text.trim(),
            medications: _medications.text.trim(),
            allergies: _allergies.text.trim(),
          );
      ref.read(startWithUploadProvider.notifier).arm();
      ref.invalidate(profileProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
      });
    }
  }

  void _next() {
    if (!_validateStep()) return;
    if (_step < 2) {
      setState(() {
        _step += 1;
        _message = null;
      });
      return;
    }
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Step ${_step + 1} of 3',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: (_step + 1) / 3),
                  const SizedBox(height: 24),
                  Text(
                    switch (_step) {
                      0 => 'About you',
                      1 => 'Body measurements',
                      _ => 'Health background',
                    },
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    switch (_step) {
                      0 => 'This personalizes your reports. It takes a minute.',
                      1 => 'Use kilograms and centimetres.',
                      _ =>
                        'Leave these blank if none apply. You can change them later.',
                    },
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_step == 0) ...[
                    TextField(
                      key: const Key('profile-name'),
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Preferred name (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('profile-age'),
                      controller: _age,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final option in const ['Female', 'Male', 'Other'])
                          ChoiceChip(
                            label: Text(option),
                            selected: _sex == option.toLowerCase(),
                            onSelected: _busy
                                ? null
                                : (_) => setState(
                                    () => _sex = option.toLowerCase(),
                                  ),
                          ),
                      ],
                    ),
                  ],
                  if (_step == 1) ...[
                    TextField(
                      key: const Key('profile-weight'),
                      controller: _weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('profile-height'),
                      controller: _height,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Height (cm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_step == 2) ...[
                    TextField(
                      key: const Key('profile-conditions'),
                      controller: _conditions,
                      decoration: const InputDecoration(
                        labelText: 'Conditions',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('profile-medications'),
                      controller: _medications,
                      decoration: const InputDecoration(
                        labelText: 'Medications',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('profile-allergies'),
                      controller: _allergies,
                      decoration: const InputDecoration(
                        labelText: 'Allergies',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    _Note(message: _message!, isError: true),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _next,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_step == 2 ? 'Scan a report' : 'Continue'),
                  ),
                  if (_step > 0) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _step -= 1;
                              _message = null;
                            }),
                      child: const Text('Back'),
                    ),
                  ],
                  if (_step == 2) ...[
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              _conditions.clear();
                              _medications.clear();
                              _allergies.clear();
                              _finish();
                            },
                      child: const Text('Skip health background'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final semantics = context.semantic;
    final base = isError ? semantics.error : semantics.success;
    final container = isError
        ? semantics.errorContainer
        : semantics.successContainer;
    final onContainer = isError
        ? semantics.onErrorContainer
        : semantics.onSuccessContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: base,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: onContainer)),
          ),
        ],
      ),
    );
  }
}
