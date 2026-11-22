import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/note_model.dart';
import '../../../routes/app_routes.dart';
import '../../key_management/providers/key_provider.dart';
import '../../notes/providers/notes_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../widgets/note_card.dart';

enum _HomeMenuAction { settings, keyManagement, about }

/// Main screen: the list (or grid) of notes.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _onMenuSelected(BuildContext context, _HomeMenuAction action) {
    switch (action) {
      case _HomeMenuAction.settings:
        AppRoutes.open(context, AppRoutes.settings);
      case _HomeMenuAction.keyManagement:
        AppRoutes.open(context, AppRoutes.keyManagement);
      case _HomeMenuAction.about:
        AppRoutes.open(context, AppRoutes.about);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final notesProvider = context.watch<NotesProvider>();
    final isGrid = settings.isGridView;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 30),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                AppConstants.appName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => AppRoutes.open(context, AppRoutes.search),
          ),
          IconButton(
            key: const Key('view-toggle'),
            tooltip: isGrid ? 'Show as list' : 'Show as grid',
            icon: Icon(
              isGrid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
            ),
            onPressed: settings.toggleViewMode,
          ),
          PopupMenuButton<_HomeMenuAction>(
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => _onMenuSelected(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _HomeMenuAction.settings,
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _HomeMenuAction.keyManagement,
                child: ListTile(
                  leading: Icon(Icons.key_outlined),
                  title: Text('Key Management'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _HomeMenuAction.about,
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('About'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: notesProvider.loadError != null && !notesProvider.isLoaded
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Your notes could not be loaded',
              message:
                  '${notesProvider.loadError!.message} '
                  'Nothing has been deleted.',
              action: FilledButton.icon(
                key: const Key('notes-retry'),
                onPressed: notesProvider.isLoading ? null : notesProvider.load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            )
          : !notesProvider.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : notesProvider.isEmpty
          ? EmptyState(
              icon: Icons.edit_note_rounded,
              title: 'No notes yet',
              message:
                  'Tap the + button to create your first note.\n'
                  'English and বাংলা are both supported.',
            )
          : _NotesBody(
              notes: notesProvider.sorted(settings.sortOrder),
              isGrid: isGrid,
              showPreview: settings.showContentPreview,
              sortOrder: settings.sortOrder,
              onSortChanged: settings.setSortOrder,
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add note',
        onPressed: () => AppRoutes.openEditor(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }
}

class _NotesBody extends StatelessWidget {
  const _NotesBody({
    required this.notes,
    required this.isGrid,
    required this.showPreview,
    required this.sortOrder,
    required this.onSortChanged,
  });

  final List<Note> notes;
  final bool isGrid;
  final bool showPreview;
  final NoteSortOrder sortOrder;
  final ValueChanged<NoteSortOrder> onSortChanged;

  static const _padding = EdgeInsets.fromLTRB(16, 4, 16, 96);

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>();
    void open(Note note) => AppRoutes.openEditor(context, noteId: note.id);

    final Widget content;
    if (isGrid) {
      content = GridView.builder(
        key: const Key('notes-grid'),
        padding: _padding,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 190,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: notes.length,
        itemBuilder: (context, index) => NoteCard(
          key: ValueKey(notes[index].id),
          note: notes[index],
          isGrid: true,
          showPreview: showPreview,
          keyAvailable: keys.isAvailable(
            notes[index].keyId,
            notes[index].keyVersion,
          ),
          onTap: () => open(notes[index]),
        ),
      );
    } else {
      content = ListView.separated(
        key: const Key('notes-list'),
        padding: _padding,
        itemCount: notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => NoteCard(
          key: ValueKey(notes[index].id),
          note: notes[index],
          showPreview: showPreview,
          keyAvailable: keys.isAvailable(
            notes[index].keyId,
            notes[index].keyVersion,
          ),
          onTap: () => open(notes[index]),
        ),
      );
    }

    return Column(
      children: [
        _SortBar(
          count: notes.length,
          sortOrder: sortOrder,
          onChanged: onSortChanged,
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.count,
    required this.sortOrder,
    required this.onChanged,
  });

  final int count;
  final NoteSortOrder sortOrder;
  final ValueChanged<NoteSortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1 ? '1 note' : '$count notes',
              style: muted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PopupMenuButton<NoteSortOrder>(
            tooltip: 'Sort notes',
            initialValue: sortOrder,
            onSelected: onChanged,
            itemBuilder: (context) => [
              for (final order in NoteSortOrder.values)
                CheckedPopupMenuItem(
                  value: order,
                  checked: order == sortOrder,
                  child: Text(order.label),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 18, color: muted?.color),
                  const SizedBox(width: 6),
                  Text(
                    sortOrder.label,
                    style: muted,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Icon(Icons.arrow_drop_down_rounded, color: muted?.color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
