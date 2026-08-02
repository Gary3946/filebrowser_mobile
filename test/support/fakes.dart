import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:filebrowser_mobile/src/api/filebrowser_client.dart';
import 'package:filebrowser_mobile/src/api/models.dart';
import 'package:filebrowser_mobile/src/auth/auth_controller.dart';
import 'package:filebrowser_mobile/src/data/preferences_store.dart';
import 'package:filebrowser_mobile/src/transfers/transfer_service.dart';
import 'package:filebrowser_mobile/src/ui/item_actions.dart';

/// [AuthController] stub exposing a fixed client/user without touching secure
/// storage or the network.
class FakeAuth extends AuthController {
  FakeAuth(this._client, this._user, PreferencesStore prefs)
      : super(prefs: prefs);

  final FileBrowserClient _client;
  final FbUser _user;

  @override
  FileBrowserClient? get client => _client;

  @override
  FbUser? get user => _user;

  @override
  Future<void> ensureFreshSession() async {}
}

/// [ItemActions] with the transfer-backed flows stubbed out — widget tests
/// have no FileDownloader / OpenFilex platform channels — while the
/// dialog-driven flows (rename, delete, share chooser, share link) stay real
/// and hit the test's mock-adapter client.
class FakeItemActions extends ItemActions {
  FakeItemActions({required super.auth, required super.prefs})
      : super(transfers: TransferService());

  final List<FbResource> openedWith = [];
  final List<FbResource> downloaded = [];
  final List<List<FbResource>> sentNative = [];

  @override
  Future<void> openWith(BuildContext context, FbResource item) async {
    openedWith.add(item);
  }

  @override
  Future<void> download(BuildContext context, FbResource item) async {
    downloaded.add(item);
  }

  @override
  Future<void> shareNative(
      BuildContext context, List<FbResource> items) async {
    sentNative.add(items);
  }
}

/// Builds a [FakeItemActions] over [client] with fresh mock preferences.
Future<FakeItemActions> fakeItemActions(FileBrowserClient client,
    {bool canModify = true}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await PreferencesStore.create();
  final auth = FakeAuth(
    client,
    FbUser(username: 'u', canCreate: true, canModify: canModify),
    prefs,
  );
  return FakeItemActions(auth: auth, prefs: prefs);
}
