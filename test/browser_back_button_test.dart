import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:filebrowser_mobile/src/api/filebrowser_client.dart';
import 'package:filebrowser_mobile/src/api/models.dart';
import 'package:filebrowser_mobile/src/auth/auth_controller.dart';
import 'package:filebrowser_mobile/src/data/preferences_store.dart';
import 'package:filebrowser_mobile/src/transfers/transfer_service.dart';
import 'package:filebrowser_mobile/src/ui/browser_screen.dart';

import 'support/l10n.dart';
import 'support/mock_adapter.dart';

class _FakeAuth extends AuthController {
  _FakeAuth(this._client, this._user, PreferencesStore prefs)
      : super(prefs: prefs);
  final FileBrowserClient _client;
  final FbUser _user;
  @override
  FileBrowserClient? get client => _client;
  @override
  FbUser? get user => _user;
}

/// Serves a two-level tree: / contains the folder `docs`, which contains the
/// folder `deep` and a file, so tests can descend two levels and walk back up.
ResponseBody _tree(RequestOptions o) {
  final path = o.uri.queryParameters['path'] ?? '/';
  switch (path) {
    case '/docs':
      return MockAdapter.json({
        'path': '/docs',
        'name': 'docs',
        'size': 0,
        'isDir': true,
        'items': [
          {'path': '/docs/deep', 'name': 'deep', 'size': 0, 'isDir': true},
          {'path': '/docs/note.txt', 'name': 'note.txt', 'size': 5, 'isDir': false},
        ],
      });
    case '/docs/deep':
      return MockAdapter.json({
        'path': '/docs/deep',
        'name': 'deep',
        'size': 0,
        'isDir': true,
        'items': [
          {'path': '/docs/deep/leaf.txt', 'name': 'leaf.txt', 'size': 5, 'isDir': false},
        ],
      });
    default:
      return MockAdapter.json({
        'path': '/',
        'name': '/',
        'size': 0,
        'isDir': true,
        'items': [
          {'path': '/docs', 'name': 'docs', 'size': 0, 'isDir': true},
          {'path': '/root.txt', 'name': 'root.txt', 'size': 10, 'isDir': false},
        ],
      });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReceiveSharingIntent.setMockValues(
        initialMedia: const [], mediaStream: const Stream.empty());
  });

  Future<void> pumpBrowser(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await PreferencesStore.create();
    final client = FileBrowserClient(
        baseUrl: 'https://demo.example.com', adapter: MockAdapter(_tree))
      ..adoptToken('tok');
    final auth = _FakeAuth(client,
        FbUser(username: 'u', canCreate: true, canModify: true), prefs);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<PreferencesStore>.value(value: prefs),
        Provider<TransferService>(create: (_) => TransferService()),
        ChangeNotifierProvider<AuthController>.value(value: auth),
      ],
      child: l10nWrap(const BrowserScreen()),
    ));
    await tester.pumpAndSettle();
  }

  /// Delivers the platform's system back, as Android does for button/gesture.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('system back walks up one directory at a time, then leaves',
      (tester) async {
    await pumpBrowser(tester);

    // Descend two levels: / -> /docs -> /docs/deep.
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    expect(find.text('note.txt'), findsOneWidget);
    await tester.tap(find.text('deep'));
    await tester.pumpAndSettle();
    expect(find.text('leaf.txt'), findsOneWidget);

    // Back: /docs/deep -> /docs.
    await systemBack(tester);
    expect(find.text('note.txt'), findsOneWidget);
    expect(find.text('leaf.txt'), findsNothing);

    // Back: /docs -> /.
    await systemBack(tester);
    expect(find.text('root.txt'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);

    // At the root there is nothing left to unwind: the pop propagates to the
    // platform (which on Android backgrounds the app).
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('system back exits selection mode before navigating up',
      (tester) async {
    await pumpBrowser(tester);
    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();

    // Arm selection mode via long-press.
    await tester.longPress(find.text('note.txt'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    // First back only leaves selection mode; still in /docs.
    await systemBack(tester);
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('note.txt'), findsOneWidget);

    // Second back now navigates up to /.
    await systemBack(tester);
    expect(find.text('root.txt'), findsOneWidget);
  });
}
