import 'package:material_ui/material_ui.dart';

import '../../../routes/app_routes.dart';

enum _InfoLanguage { english, bangla }

class _InfoSection {
  const _InfoSection(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const List<_InfoSection> _english = [
  _InfoSection(
    Icons.lock_outline_rounded,
    'What is encryption?',
    'Encryption changes readable text into scrambled text. Only someone '
        'with the right key can change it back and read it.',
  ),
  _InfoSection(
    Icons.key_outlined,
    'Your own key',
    'You create keys in Key Management. Each key is a random 2×2 Hill '
        'Cipher matrix kept in secure storage on this device. Only its name '
        'and details are shown; the key values are never displayed.',
  ),
  _InfoSection(
    Icons.toggle_on_outlined,
    'Always optional',
    'You choose which notes to encrypt, one at a time. You can keep '
        'writing normal notes without ever creating a key.',
  ),
  _InfoSection(
    Icons.text_fields_rounded,
    'What is encrypted',
    'The title and the text of the note are both encrypted, word by word. '
        'Spaces, line breaks and punctuation stay where they are, so the '
        'shape of the note is still visible. Emoji are also left as they '
        'are.',
  ),
  _InfoSection(
    Icons.edit_note_rounded,
    'Reading and editing',
    'Open an encrypted note and tap Decrypt. The readable text is kept only '
        'while the note is open. When you finish, encrypt it again or save '
        'it as plain text. Encrypted notes are not included in search.',
  ),
  _InfoSection(
    Icons.key_off_outlined,
    'Keep your keys',
    'If a key is deleted or lost (for example, by uninstalling the app), '
        'notes encrypted with it cannot be read again. A key that is used by '
        'notes cannot be deleted in the app.',
  ),
  _InfoSection(
    Icons.warning_amber_rounded,
    'Important: learning-level security',
    'The Hill Cipher is a classical, educational cipher. It is easy to '
        'break with modern methods, and it cannot detect if encrypted text '
        'was changed. Do not use it to protect passwords, bank details or '
        'other sensitive information.',
  ),
];

const List<_InfoSection> _bangla = [
  _InfoSection(
    Icons.lock_outline_rounded,
    'এনক্রিপশন কী?',
    'এনক্রিপশন পড়া যায় এমন লেখাকে এলোমেলো লেখায় বদলে দেয়। সঠিক কী '
        '(key) থাকলেই কেবল সেটি আবার পড়া যায়।',
  ),
  _InfoSection(
    Icons.key_outlined,
    'আপনার নিজের কী',
    'কী ম্যানেজমেন্টে আপনি কী তৈরি করেন। প্রতিটি কী একটি র‍্যান্ডম ২×২ হিল '
        'সাইফার ম্যাট্রিক্স, যা এই ডিভাইসের সুরক্ষিত স্টোরেজে রাখা হয়। শুধু এর '
        'নাম ও তথ্য দেখানো হয়; কী-এর মান কখনো দেখানো হয় না।',
  ),
  _InfoSection(
    Icons.toggle_on_outlined,
    'সবসময় ঐচ্ছিক',
    'কোন নোট এনক্রিপ্ট করবেন তা আপনি একটি একটি করে বেছে নেন। কোনো কী তৈরি '
        'না করেও আপনি সাধারণ নোট লিখতে পারবেন।',
  ),
  _InfoSection(
    Icons.text_fields_rounded,
    'কী এনক্রিপ্ট হয়',
    'নোটের শিরোনাম ও লেখা দুটোই শব্দ ধরে ধরে এনক্রিপ্ট হয়। স্পেস, নতুন লাইন '
        'ও যতিচিহ্ন আগের জায়গায় থাকে, তাই নোটের গঠন বোঝা যায়। ইমোজিও যেমন '
        'আছে তেমনই থাকে।',
  ),
  _InfoSection(
    Icons.edit_note_rounded,
    'পড়া ও সম্পাদনা',
    'এনক্রিপ্ট করা নোট খুলে "Decrypt" চাপুন। নোট খোলা থাকা পর্যন্তই পড়ার মতো '
        'লেখা রাখা হয়। কাজ শেষে আবার এনক্রিপ্ট করুন বা সাধারণ লেখা হিসেবে '
        'সংরক্ষণ করুন। এনক্রিপ্ট করা নোট সার্চে আসে না।',
  ),
  _InfoSection(
    Icons.key_off_outlined,
    'কী সংরক্ষণ করুন',
    'কোনো কী মুছে গেলে বা হারালে (যেমন অ্যাপ আনইনস্টল করলে) সেই কী দিয়ে '
        'এনক্রিপ্ট করা নোট আর পড়া যাবে না। যে কী কোনো নোটে ব্যবহৃত হচ্ছে, '
        'অ্যাপে তা মোছা যায় না।',
  ),
  _InfoSection(
    Icons.warning_amber_rounded,
    'গুরুত্বপূর্ণ: শিক্ষামূলক নিরাপত্তা',
    'হিল সাইফার একটি পুরোনো, শিক্ষামূলক সাইফার। আধুনিক পদ্ধতিতে এটি সহজেই '
        'ভাঙা যায়, এবং এনক্রিপ্ট করা লেখা বদলানো হলে তা ধরতে পারে না। '
        'পাসওয়ার্ড, ব্যাংকের তথ্য বা অন্য সংবেদনশীল তথ্য রক্ষায় এটি ব্যবহার '
        'করবেন না।',
  ),
];

/// Plain-language explanation of the planned encryption feature, in English
/// and Bangla.
class EncryptionInfoScreen extends StatefulWidget {
  const EncryptionInfoScreen({super.key});

  @override
  State<EncryptionInfoScreen> createState() => _EncryptionInfoScreenState();
}

class _EncryptionInfoScreenState extends State<EncryptionInfoScreen> {
  _InfoLanguage _language = _InfoLanguage.english;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sections = _language == _InfoLanguage.english ? _english : _bangla;

    return Scaffold(
      appBar: AppBar(title: const Text('Encryption information')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: SegmentedButton<_InfoLanguage>(
              key: const Key('info-language'),
              segments: const [
                ButtonSegment(
                  value: _InfoLanguage.english,
                  label: Text('English'),
                ),
                ButtonSegment(
                  value: _InfoLanguage.bangla,
                  label: Text('বাংলা'),
                ),
              ],
              selected: {_language},
              onSelectionChanged: (value) =>
                  setState(() => _language = value.first),
            ),
          ),
          const SizedBox(height: 16),
          for (final (index, section) in sections.indexed) ...[
            Card(
              color: index == sections.length - 1
                  ? scheme.errorContainer.withValues(alpha: 0.5)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      section.icon,
                      color: index == sections.length - 1
                          ? scheme.error
                          : scheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            section.body,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.55,
                              color: scheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => AppRoutes.open(context, AppRoutes.keyManagement),
            icon: const Icon(Icons.key_outlined),
            label: Text(
              _language == _InfoLanguage.english
                  ? 'Open Key Management'
                  : 'কী ম্যানেজমেন্ট খুলুন',
            ),
          ),
        ],
      ),
    );
  }
}
