/// In-app policy and support pages linked from Settings.
library;

import 'package:flutter/material.dart';

import '../../../core/legal/legal_constants.dart';
import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => const _PolicyPage(
    title: 'Privacy',
    sections: <_PolicySection>[
      _PolicySection(
        title: 'Information in MedAIx',
        body:
            'MedAIx handles account details, health answers and consent, '
            'reports you upload and their extracted information, and wellness '
            'logs you choose to record.',
      ),
      _PolicySection(
        title: 'How information is used',
        body:
            'The app uses this information to provide your account, display '
            'and explain reports, and support the features you choose to use. '
            'Report images or PDFs are sent for reading when you upload them.',
      ),
      _PolicySection(
        title: 'Storage and deletion',
        body:
            'Account and health information is associated with your account. '
            'Some wellness information is cached on this device for offline '
            'use. Use Settings → Profile and health details → Delete my data '
            'to request deletion of your health details and reports. Your '
            'sign-in account, name, and email remain.',
      ),
      _PolicySection(
        title: 'Questions',
        body:
            'For privacy questions, contact support at $kSupportEmail. Do not '
            'send report photos by email.',
      ),
      _PolicySection(
        title: 'Review status',
        body:
            'This in-app privacy notice is a draft based on current app '
            'behavior. The owner should review it before release.',
      ),
    ],
  );
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _PolicyPage(
    title: 'Terms',
    sections: <_PolicySection>[
      _PolicySection(
        title: 'What MedAIx does',
        body:
            'MedAIx helps you organize lab reports and understand their '
            'contents. Information may be incomplete or incorrect; check the '
            'original report when something matters.',
      ),
      _PolicySection(
        title: 'Not medical advice',
        body:
            'MedAIx explains reports; it is not a diagnosis and does not '
            'replace advice from a qualified health professional. Do not use '
            'the app for emergencies or to delay medical care.',
      ),
      _PolicySection(
        title: 'Your account and information',
        body:
            'Keep your sign-in credentials private. Only upload information '
            'you are allowed to provide. You can delete health details and '
            'reports from Settings → Profile and health details.',
      ),
      _PolicySection(
        title: 'Support and draft status',
        body:
            'For help, contact $kSupportEmail. These in-app terms are a draft '
            'for owner review before release.',
      ),
    ],
  );
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: AppScreen(
      header: const ScreenHeader(title: 'Contact support', showBack: true),
      children: [
        const SectionTitle('Get help', first: true),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < kSupportParagraphs.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpace.lg),
                Text(
                  kSupportParagraphs[i],
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _PolicyPage extends StatelessWidget {
  const _PolicyPage({required this.title, required this.sections});

  final String title;
  final List<_PolicySection> sections;

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: AppScreen(
      header: ScreenHeader(title: title, showBack: true),
      children: [
        for (int i = 0; i < sections.length; i++) ...[
          SectionTitle(sections[i].title, first: i == 0),
          AppCard(
            child: Text(
              sections[i].body,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    ),
  );
}

class _PolicySection {
  const _PolicySection({required this.title, required this.body});

  final String title;
  final String body;
}
