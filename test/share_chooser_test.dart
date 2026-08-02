import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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

import 'support/fakes.dart';
import 'support/l10n.dart';
import 'support/mock_adapter.dart';

// Two generic files (tap -> action sheet, not a viewer) and one folder.
ResponseBody _listing(RequestOptions _) => MockAdapter.json({
      'path': '/',
      'name': '/',
      'size': 0,
      'isDir': true,
      'items': [
        {'path': '/a.bin', 'name': 'a.bin', 'size': 10, 'isDir': false},
        {'path': '/b.bin', 'name': 'b.bin', 'size': 30, 'isDir': false},
        {'path': '/docs/', 'name': 'docs', 'size': 0, 'isDir': true},
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReceiveSharingIntent.setMockValues(
        initialMedia: const [], mediaStream: const Stream.empty());
  });

  Future<void> pumpBrowser(WidgetTester tester,
      {bool canModify = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await PreferencesStore.create();
    final client = FileBrowserClient(
        baseUrl: 'https://demo.example.com', adapter: MockAdapter(_listing))
      ..adoptToken('tok');
    final auth = FakeAuth(client,
        FbUser(username: 'u', canCreate: true, canModify: canModify), prefs);
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

  ListTile tileWithText(WidgetTester tester, String text) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, text));

  testWidgets(
      'multi-selection share opens the chooser: send enabled, link disabled',
      (tester) async {
    await pumpBrowser(tester);

    await tester.longPress(find.text('a.bin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b.bin'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget); // chooser header
    expect(tileWithText(tester, 'Send 2 files').enabled, isTrue);
    expect(tileWithText(tester, 'Share link').enabled, isFalse);
    expect(find.text('Select a single item to share a link'), findsOneWidget);
  });

  testWidgets(
      'single file: both methods enabled; link runs the create-share dialog',
      (tester) async {
    await pumpBrowser(tester);

    await tester.longPress(find.text('a.bin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(tileWithText(tester, 'Send file').enabled, isTrue);
    expect(tileWithText(tester, 'Share link').enabled, isTrue);

    await tester.tap(find.text('Share link'));
    await tester.pumpAndSettle();
    expect(find.text('Create link'), findsOneWidget);
  });

  testWidgets('a folder in the selection disables sending copies',
      (tester) async {
    await pumpBrowser(tester);

    await tester.longPress(find.text('docs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.bin'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(tileWithText(tester, 'Send 2 files').enabled, isFalse);
    expect(find.text("Folders can't be sent as files"), findsOneWidget);
  });

  testWidgets('per-item sheet offers send-copy and share-link', (tester) async {
    await pumpBrowser(tester);

    await tester.tap(find.text('a.bin'));
    await tester.pumpAndSettle();

    expect(find.text('Send file'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets('per-item sheet hides rename/delete without modify permission',
      (tester) async {
    await pumpBrowser(tester, canModify: false);

    await tester.tap(find.text('a.bin'));
    await tester.pumpAndSettle();

    expect(find.text('Send file'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });
}
