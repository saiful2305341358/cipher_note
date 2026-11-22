import 'package:material_ui/material_ui.dart';

import '../features/about/screens/about_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/key_management/screens/key_management_screen.dart';
import '../features/notes/screens/note_editor_screen.dart';
import '../features/search/screens/search_screen.dart';
import '../features/settings/screens/encryption_info_screen.dart';
import '../features/settings/screens/settings_screen.dart';

/// Route names and navigation helpers.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String editor = '/editor';
  static const String search = '/search';
  static const String settings = '/settings';
  static const String keyManagement = '/key-management';
  static const String encryptionInfo = '/encryption-info';
  static const String about = '/about';

  /// Tracks the names of the routes currently on the navigator stack so that
  /// [open] can avoid pushing duplicate screens.
  static final RouteStackObserver observer = RouteStackObserver();

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final Widget page;
    switch (settings.name) {
      case home:
        page = const HomeScreen();
      case editor:
        final args = settings.arguments;
        page = NoteEditorScreen(noteId: args is String ? args : null);
      case search:
        page = const SearchScreen();
      case AppRoutes.settings:
        page = const SettingsScreen();
      case keyManagement:
        page = const KeyManagementScreen();
      case encryptionInfo:
        page = const EncryptionInfoScreen();
      case about:
        page = const AboutScreen();
      default:
        return null;
    }
    return MaterialPageRoute<void>(builder: (_) => page, settings: settings);
  }

  /// Opens the screen [name]. If that screen is already on the stack the
  /// navigator returns to it instead of creating a second copy.
  static Future<void> open(BuildContext context, String name) async {
    final navigator = Navigator.of(context);
    if (observer.contains(name)) {
      navigator.popUntil(ModalRoute.withName(name));
      return;
    }
    await navigator.pushNamed(name);
  }

  /// Opens the note editor for an existing note, or for a new note when
  /// [noteId] is null. Ignored if an editor is already the top screen (for
  /// example after an accidental double tap).
  static Future<void> openEditor(BuildContext context, {String? noteId}) async {
    if (observer.top == editor) return;
    await Navigator.of(context).pushNamed(editor, arguments: noteId);
  }
}

/// Keeps a list of route names mirroring the navigator stack.
class RouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  bool contains(String name) {
    _prune();
    return _stack.any((r) => r.settings.name == name);
  }

  String? get top {
    _prune();
    return _stack.isEmpty ? null : _stack.last.settings.name;
  }

  /// Drops routes that are no longer on any navigator (e.g. after the app
  /// widget was rebuilt from scratch).
  void _prune() => _stack.removeWhere((r) => !r.isActive);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0 && newRoute is PageRoute) {
      _stack[index] = newRoute;
    } else if (index >= 0) {
      _stack.removeAt(index);
    }
  }
}
