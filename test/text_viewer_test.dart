import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:filebrowser_mobile/src/api/filebrowser_client.dart';
import 'package:filebrowser_mobile/src/api/models.dart';
import 'package:filebrowser_mobile/src/ui/text_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/l10n.dart';
import 'support/mock_adapter.dart';

const _jwt = 'eyJhbGciOiJIUzI1NiJ9.'
    'eyJleHAiOjk5OTk5OTk5OTksInVzZXJuYW1lIjoidCJ9.'
    'sig';

FileBrowserClient _client(MockAdapter adapter) =>
    FileBrowserClient(baseUrl: 'https://s.example', adapter: adapter)
      ..adoptToken(_jwt)
      ..setSource('files');

FbResource _file(String name, int size) =>
    FbResource(path: '/$name', name: name, size: size, isDir: false);

Widget _wrap(Widget child) => l10nWrap(child);

void main() {
  testWidgets('renders fetched text and requests the right URL',
      (tester) async {
    final adapter = MockAdapter((_) => ResponseBody.fromString(
        'hello quantum\nline two', 200,
        headers: {
          Headers.contentTypeHeader: ['text/plain']
        }));
    await tester.pumpWidget(_wrap(TextViewerScreen(
      client: _client(adapter),
      resource: _file('notes.txt', 22),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('hello quantum'), findsOneWidget);
    final req = adapter.requests.single;
    expect(req.uri.path, '/api/resources/download');
    expect(req.uri.queryParameters['file'], '/notes.txt');
    expect(req.uri.queryParameters['source'], 'files');
  });

  testWidgets('a file over the cap is not fetched; offers Open with…',
      (tester) async {
    final adapter = MockAdapter((_) => MockAdapter.json({}));
    final client = _client(adapter);
    final actions = await fakeItemActions(client);
    final resource = _file('huge.log', TextViewerScreen.maxPreviewBytes + 1);
    await tester.pumpWidget(_wrap(TextViewerScreen(
      client: client,
      resource: resource,
      actions: actions,
    )));
    await tester.pumpAndSettle();

    expect(adapter.requests, isEmpty); // never downloaded
    expect(find.textContaining('Too large to preview'), findsOneWidget);
    // The body CTA (not the app-bar menu) hands off to the shared flow.
    await tester.tap(find.widgetWithText(FilledButton, 'Open with…'));
    await tester.pumpAndSettle();
    expect(actions.openedWith.single.path, resource.path);
  });

  testWidgets('a fetch failure shows the copyable error view with retry',
      (tester) async {
    var calls = 0;
    final adapter = MockAdapter((_) {
      calls++;
      if (calls == 1) return MockAdapter.json({}, status: 500);
      return ResponseBody.fromString('recovered', 200, headers: {
        Headers.contentTypeHeader: ['text/plain']
      });
    });
    await tester.pumpWidget(_wrap(TextViewerScreen(
      client: _client(adapter),
      resource: _file('flaky.txt', 9),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load flaky.txt'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('recovered'), findsOneWidget);
  });

  testWidgets('invalid UTF-8 decodes leniently instead of crashing',
      (tester) async {
    final adapter = MockAdapter((_) => ResponseBody.fromBytes(
        [0x68, 0x69, 0xFF, 0xFE, 0x21], 200,
        headers: {
          Headers.contentTypeHeader: ['application/octet-stream']
        }));
    await tester.pumpWidget(_wrap(TextViewerScreen(
      client: _client(adapter),
      resource: _file('weird.txt', 5),
    )));
    await tester.pumpAndSettle();

    // 'hi' survives; the invalid bytes become U+FFFD.
    expect(find.textContaining('hi'), findsOneWidget);
    expect(find.textContaining(utf8.decode([0xEF, 0xBF, 0xBD])), findsOneWidget);
  });
}
