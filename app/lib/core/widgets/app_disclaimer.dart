/// Shared, quiet disclaimer for report and trend content.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AppDisclaimer extends StatelessWidget {
  const AppDisclaimer({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'MedAIx explains reports; it is not a diagnosis.',
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.colors.muted),
    textAlign: TextAlign.start,
  );
}
