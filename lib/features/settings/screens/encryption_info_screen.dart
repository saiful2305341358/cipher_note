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
    'This app will use a key that you create yourself. The key will be '
        'used with the Hill Cipher method to lock and unlock notes.',
  ),
  _InfoSection(
    Icons.toggle_on_outlined,
    'Always optional',
    'Encryption will be optional and chosen for each note. You can keep '
        'writing normal notes without ever creating a key.',
  ),
  _InfoSection(
    Icons.schedule_rounded,
    'Not available yet',
    'Encryption is planned for a future development phase. Right now, '
        'every note is stored as normal, readable text.',
  ),
  _InfoSection(
    Icons.warning_amber_rounded,
    'Important: learning-level security',
    'The Hill Cipher is a classical, educational cipher. It is easy to '
        'break with modern methods and should not be used to protect '
        'passwords, bank details or other sensitive information.',
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
    'এই অ্যাপ আপনার নিজের তৈরি করা একটি কী ব্যবহার করবে। নোট লক ও আনলক '
        'করতে কী-টি হিল সাইফার (Hill Cipher) পদ্ধতির সাথে ব্যবহার করা হবে।',
  ),
  _InfoSection(
    Icons.toggle_on_outlined,
    'সবসময় ঐচ্ছিক',
    'এনক্রিপশন ঐচ্ছিক থাকবে এবং প্রতিটি নোটের জন্য আলাদাভাবে বেছে নেওয়া '
        'যাবে। কোনো কী তৈরি না করেও আপনি সাধারণ নোট লিখতে পারবেন।',
  ),
  _InfoSection(
    Icons.schedule_rounded,
    'এখনও চালু হয়নি',
    'এনক্রিপশন ভবিষ্যতের একটি ধাপে যুক্ত করা হবে। এখন সব নোট সাধারণ, '
        'পড়া যায় এমন লেখা হিসেবে রাখা হয়।',
  ),
  _InfoSection(
    Icons.warning_amber_rounded,
    'গুরুত্বপূর্ণ: শিক্ষামূলক নিরাপত্তা',
    'হিল সাইফার একটি পুরোনো, শিক্ষামূলক সাইফার। আধুনিক পদ্ধতিতে এটি সহজেই '
        'ভাঙা যায়, তাই পাসওয়ার্ড, ব্যাংকের তথ্য বা অন্য সংবেদনশীল তথ্য রক্ষায় '
        'এটি ব্যবহার করবেন না।',
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
