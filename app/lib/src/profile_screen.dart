/// View and edit the signed-in patient's profile.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'providers.dart';
import 'theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return profile.when(
      skipLoadingOnReload: true,
      loading: () => const _StatusScaffold(
        title: 'Your profile',
        message: 'Loading your profile',
        busy: true,
      ),
      error: (error, _) => _StatusScaffold(
        title: 'Your profile',
        message: error is ApiException
            ? error.message
            : 'Could not load your profile.',
        onRetry: () => ref.invalidate(profileProvider),
      ),
      data: (value) => _ProfileForm(profile: value),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final PatientProfile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _weight;
  late final TextEditingController _height;
  late final TextEditingController _conditions;
  late final TextEditingController _medications;
  late final TextEditingController _allergies;
  late String _sex;
  var _busy = false;
  String? _message;
  var _messageIsError = true;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile.name ?? '');
    _age = TextEditingController(text: profile.age?.toString() ?? '');
    _weight = TextEditingController(
      text: profile.weight == null ? '' : _trimNumber(profile.weight!),
    );
    _height = TextEditingController(
      text: profile.height == null ? '' : _trimNumber(profile.height!),
    );
    _conditions = TextEditingController(text: profile.conditions);
    _medications = TextEditingController(text: profile.medications);
    _allergies = TextEditingController(text: profile.allergies);
    _sex = profile.sex ?? '';
  }

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

  String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  Future<void> _save() async {
    final age = int.tryParse(_age.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    final height = double.tryParse(_height.text.trim());
    String? message;
    if (age == null || age < 1 || age > 120) {
      message = 'Enter an age from 1 to 120.';
    } else if (_sex.isEmpty) {
      message = 'Choose female, male, or other.';
    } else if (weight == null || weight <= 0 || weight > 500) {
      message = 'Enter a weight in kilograms, up to 500.';
    } else if (height == null || height <= 30 || height > 250) {
      message = 'Enter a height in centimetres, from 31 to 250.';
    }
    if (message != null) {
      setState(() {
        _message = message;
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .saveProfile(
            name: _name.text.trim(),
            age: age!,
            weight: weight!,
            height: height!,
            sex: _sex,
            conditions: _conditions.text.trim(),
            medications: _medications.text.trim(),
            allergies: _allergies.text.trim(),
          );
      ref.invalidate(profileProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Profile saved.';
        _messageIsError = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
        _messageIsError = true;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete profile'),
        content: const Text(
          'Your MedAIx profile and lab reports will be deleted. '
          'You can sign in again afterwards. Your sign-in email stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep profile'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete profile'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).deleteProfile();
      ref.invalidate(profileProvider);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
        _messageIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Preferred name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final option in const ['Female', 'Male', 'Other'])
                        ChoiceChip(
                          label: Text(option),
                          selected: _sex == option.toLowerCase(),
                          onSelected: _busy
                              ? null
                              : (_) =>
                                    setState(() => _sex = option.toLowerCase()),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
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
                    controller: _height,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Height (cm)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _conditions,
                    decoration: const InputDecoration(
                      labelText: 'Conditions',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _medications,
                    decoration: const InputDecoration(
                      labelText: 'Medications',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _allergies,
                    decoration: const InputDecoration(
                      labelText: 'Allergies',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    _Banner(message: _message!, isError: _messageIsError),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save profile'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: context.semantic.error,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete profile'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({
    required this.title,
    required this.message,
    this.busy = false,
    this.onRetry,
  });

  final String title;
  final String message;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
              ],
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

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
