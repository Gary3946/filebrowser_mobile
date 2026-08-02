import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filebrowser_mobile/src/api/filebrowser_client.dart';
import 'package:filebrowser_mobile/src/api/models.dart';
import 'package:filebrowser_mobile/src/ui/text_viewer_screen.dart';

import 'support/fakes.dart';
import 'support/l10n.dart';
import 'support/mock_adapter.dart';

// The menu is one shared widget; these tests exercise it on the text viewer
// (the only viewer whose body needs no image/video platform plumbing).

FbResource _file(String name, int size) =>
    FbResource(path: '/$name', name: name, size: size, isDir: false);

FileBrowserClient _client(MockAdapter adapter) =>
    FileBrowserClient(baseUrl: 'https://s.example', adapter: adapter)
      ..adoptToken('tok')
      ..setSource('files');

/// Text-viewer fetch succeeds; rename (PATCH) and delete (DELETE) succeed.
ResponseBody _serve(RequestOptions o) {
  if (o.method == 'GET') {
    return ResponseBody.fromString('hello', 200,
        headers: {Headers.contentTypeHeader: ['text/plain']});
  }
  return MockAdapter.text('');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Pushes the viewer from a stub home screen so pops land somewhere real.
  Future<void> pumpViewer(
    WidgetTester tester, {
    required FileBrowserClient client,
    required FakeItemActions actions,
    required FbResource resource,
    VoidCallback? onChanged,
  }) async {
    await tester.pumpWidget(l10nWrap(Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => TextViewerScreen(
            client: client,
            resource: resource,
            actions: actions,
            onChanged: onChanged,
          ),
        )),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
  }

  testWidgets('menu lists the full action sweep for a modifying user',
      (tester) async {
    final client = _client(MockAdapter(_serve));
    final actions = await fakeItemActions(client);
    await pumpViewer(tester,
        client: client, actions: actions, resource: _file('notes.txt', 5));

    await openMenu(tester);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Open with…'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('rename/delete are hidden without modify permission',
      (tester) async {
    final client = _client(MockAdapter(_serve));
    final actions = await fakeItemActions(client, canModify: false);
    await pumpViewer(tester,
        client: client, actions: actions, resource: _file('notes.txt', 5));

    await openMenu(tester);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('Download dispatches the shown resource to the shared flow',
      (tester) async {
    final client = _client(MockAdapter(_serve));
    final actions = await fakeItemActions(client);
    final res = _file('notes.txt', 5);
    await pumpViewer(tester, client: client, actions: actions, resource: res);

    await openMenu(tester);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(actions.downloaded.single.path, res.path);
  });

  testWidgets('Share opens the chooser; send-copy hands off the file',
      (tester) async {
    final client = _client(MockAdapter(_serve));
    final actions = await fakeItemActions(client);
    final res = _file('notes.txt', 5);
    await pumpViewer(tester, client: client, actions: actions, resource: res);

    await openMenu(tester);
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(find.text('Send file'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);

    await tester.tap(find.text('Send file'));
    await tester.pumpAndSettle();
    expect(actions.sentNative.single.single.path, res.path);
  });

  testWidgets('Delete confirms, notifies the browser, and closes the viewer',
      (tester) async {
    final adapter = MockAdapter(_serve);
    final client = _client(adapter);
    final actions = await fakeItemActions(client);
    var changed = false;
    await pumpViewer(tester,
        client: client,
        actions: actions,
        resource: _file('notes.txt', 5),
        onChanged: () => changed = true);

    await openMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete notes.txt?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(changed, isTrue);
    expect(adapter.requests.any((r) => r.method == 'DELETE'), isTrue);
    // The viewer popped back to the stub home screen.
    expect(find.text('open'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
  });
}
