import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/text_utils.dart';
import '../../../data/models/note_model.dart';

/// A note shown as a rounded, coloured card. Used by the home screen (list
/// and grid layouts) and by search results.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.isGrid = false,
    this.showPreview = true,
    this.highlight,
    this.keyAvailable = true,
  });

  final Note note;
  final VoidCallback onTap;
  final bool isGrid;
  final bool showPreview;

  /// Optional search text to highlight in the title and preview.
  final String? highlight;

  /// For encrypted notes: whether the key needed to read it is on this
  /// device.
  final bool keyAvailable;

  /// Content preview text. When the note has no title, the first line is
  /// used as the title, so the preview starts from the second line.
  String get _preview {
    if (note.title.trim().isNotEmpty) return TextUtils.singleLine(note.content);
    final lines = note.content.trim().split('\n');
    return TextUtils.singleLine(lines.skip(1).join(' '));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final scheme = theme.colorScheme;
    final background = AppColors.noteBackground(note.color, brightness);
    final accent = AppColors.noteAccent(note.color, brightness);
    // Encrypted notes never show their stored text (ciphertext) or title.
    final preview = note.isEncrypted
        ? (keyAvailable ? 'Locked' : 'Key unavailable on this device')
        : _preview;
    final showBody = note.isEncrypted || (showPreview && preview.isNotEmpty);

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final previewStyle = theme.textTheme.bodyMedium?.copyWith(
      color: note.isEncrypted && !keyAvailable
          ? scheme.error
          : scheme.onSurface.withValues(alpha: 0.72),
      fontStyle: note.isEncrypted ? FontStyle.italic : null,
      height: 1.4,
    );
    final dateStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final date = Text(DateFormatter.short(note.updatedAt), style: dateStyle);
    final lock = note.isEncrypted
        ? Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              keyAvailable ? Icons.lock_rounded : Icons.key_off_rounded,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
          )
        : const SizedBox.shrink();

    final Widget body;
    if (isGrid) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HighlightedText(
            note.displayTitle,
            query: highlight,
            style: titleStyle,
            maxLines: 2,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: showBody
                ? _HighlightedText(
                    preview,
                    query: highlight,
                    style: previewStyle,
                    maxLines: 5,
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          Row(children: [lock, date]),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HighlightedText(
                  note.displayTitle,
                  query: highlight,
                  style: titleStyle,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [lock, date],
                ),
              ),
            ],
          ),
          if (showBody) ...[
            const SizedBox(height: 4),
            _HighlightedText(
              preview,
              query: highlight,
              style: previewStyle,
              maxLines: 2,
            ),
          ],
        ],
      );
    }

    return Semantics(
      button: true,
      label: note.isEncrypted
          ? 'Encrypted note${keyAvailable ? '' : ', key unavailable'}'
          : 'Note: ${note.displayTitle}',
      excludeSemantics: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: brightness == Brightness.light
              ? [
                  BoxShadow(
                    color: AppColors.textPrimary.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: accent.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// Text that bolds and tints occurrences of [query] (case-insensitive).
class _HighlightedText extends StatelessWidget {
  const _HighlightedText(
    this.text, {
    required this.query,
    required this.style,
    required this.maxLines,
  });

  final String text;
  final String? query;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final q = query?.trim() ?? '';
    if (q.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = TextUtils.searchKey(text);
    final lowerQuery = TextUtils.searchKey(q);
    final primary = Theme.of(context).colorScheme.primary;
    final spans = <TextSpan>[];
    var start = 0;
    // Only highlight when lower-casing kept the string length, so indices
    // map back onto the original text safely.
    if (lowerText.length == text.length) {
      while (true) {
        final index = lowerText.indexOf(lowerQuery, start);
        if (index < 0) break;
        if (index > start) {
          spans.add(TextSpan(text: text.substring(start, index)));
        }
        spans.add(
          TextSpan(
            text: text.substring(index, index + lowerQuery.length),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: primary,
              backgroundColor: primary.withValues(alpha: 0.12),
            ),
          ),
        );
        start = index + lowerQuery.length;
      }
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
