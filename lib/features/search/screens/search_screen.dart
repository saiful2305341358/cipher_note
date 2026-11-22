import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../routes/app_routes.dart';
import '../../home/widgets/note_card.dart';
import '../../notes/providers/notes_provider.dart';

/// Searches note titles and content (English and Bangla) as the user types.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notesProvider = context.watch<NotesProvider>();
    final query = _controller.text;
    final results = notesProvider.search(query);

    final Widget body;
    if (query.trim().isEmpty) {
      body = EmptyState(
        icon: Icons.manage_search_rounded,
        title: 'Search your notes',
        message: notesProvider.isEmpty
            ? 'You have no notes yet. Notes you create will be searchable here.'
            : 'Type a word in English or বাংলা to find matching titles and content.',
      );
    } else if (results.isEmpty) {
      body = EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results',
        message: 'No notes match “${query.trim()}”.',
      );
    } else {
      body = ListView.separated(
        key: const Key('search-results'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: results.length + 1,
        separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 4 : 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                results.length == 1 ? '1 result' : '${results.length} results',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            );
          }
          final note = results[index - 1];
          return NoteCard(
            key: ValueKey(note.id),
            note: note,
            highlight: query,
            onTap: () {
              FocusScope.of(context).unfocus();
              AppRoutes.openEditor(context, noteId: note.id);
            },
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            key: const Key('search-field'),
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: 'Search notes',
              filled: true,
              fillColor: scheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('search-clear'),
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _controller.clear,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.primary, width: 1.5),
              ),
            ),
          ),
        ),
      ),
      body: body,
    );
  }
}
