/// App-owned contact and policy destinations. Values below are the existing
/// destinations; the owner must verify them before release.
library;

// OWNER: verify domain and mailbox before release
const String kTermsUrl = 'https://medaix.app/terms';
const String kPrivacyUrl = 'https://medaix.app/privacy';
const String kSupportEmail = 'synctaha@gmail.com';
const String kSupportResponseTime = 'We reply within two working days.';

const List<String> kSupportParagraphs = <String>[
  'Email $kSupportEmail with a short description of what happened.',
  'Please don’t include report photos in the email.',
  kSupportResponseTime,
  'For anything urgent about your health, contact your doctor or local '
      'emergency services.',
];
