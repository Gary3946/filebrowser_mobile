import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../api/filebrowser_client.dart';
import '../api/models.dart';
import '../auth/auth_controller.dart';
import '../data/preferences_store.dart';
import '../transfers/transfer_service.dart';
import 'error_display.dart';
import 'file_details_sheet.dart';
import 'share_actions.dart';
import 'share_dialog.dart';

/// The single-item flows (download, open-with, share, rename, delete, …),
/// factored out of `BrowserScreen` so every surface that shows one resource —
/// the browser's action sheet, the selection bar, and the media/text viewers
/// (via [ItemActionsMenu]) — drives the identical implementation.
///
/// Design rules that keep this reusable:
///  - Stateless: dependencies are final, all UI state lives in the dialogs.
///    Construct on demand with [ItemActions.of]; instances are cheap.
///  - Methods take the calling screen's [BuildContext] and never navigate.
///    Mutating flows return whether they changed the server ([rename],
///    [delete], [showActionsSheet]) so the caller decides what a change means
///    on its own screen (refresh the listing, pop the viewer, …).
class ItemActions {
  ItemActions({
    required this.auth,
    required this.transfers,
    required this.prefs,
  });

  /// Resolves the dependencies from the provider tree of [context].
  factory ItemActions.of(BuildContext context) => ItemActions(
        auth: context.read<AuthController>(),
        transfers: context.read<TransferService>(),
        prefs: context.read<PreferencesStore>(),
      );

  final AuthController auth;
  final TransferService transfers;
  final PreferencesStore prefs;

  /// Always resolved through [auth]: an irrecoverable 401 re-runs the direct
  /// login, which *replaces* the controller's client instance — a client
  /// captured at construction would silently go stale.
  FileBrowserClient get client => auth.client!;

  /// Whether the signed-in user may rename/delete (JWT `modify` permission).
  bool get canModify => auth.user?.canModify ?? false;

  /// Refreshes the session so a long transfer carries a current token, then
  /// returns it (or null if the session is gone). Call immediately before
  /// enqueuing. Reads [client] after the refresh — see the getter's note.
  Future<String?> _freshToken() async {
    await auth.ensureFreshSession();
    return client.token;
  }

  // --- download / open-with --------------------------------------------------

  /// Asks where to save, then enqueues a background download of [item]
  /// (folders arrive as a server-built zip).
  Future<void> download(BuildContext context, FbResource item) async {
    final loc = AppLocalizations.of(context);
    final choice = await chooseSaveLocation(context);
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final token = await _freshToken();
    if (token == null) {
      showErrorSnackBar(messenger, loc.errorSessionExpiredDownload);
      return;
    }
    final url =
        client.rawDownloadUri(item.path, algo: item.isDir ? 'zip' : null);
    await transfers.download(
      downloadUrl: url,
      token: token,
      filename: item.isDir ? '${item.name}.zip' : item.name,
      directory: choice.directory,
    );
    messenger.showSnackBar(
        SnackBar(content: Text(loc.browserDownloadingItem(item.name))));
  }

  /// Downloads [item] to the app cache and hands it to a native Android app
  /// via open-with. A no-app-available result — or any other failure — is
  /// surfaced as a copyable snackbar.
  Future<void> openWith(BuildContext context, FbResource item) async {
    final messenger = ScaffoldMessenger.of(context);
    final loc = AppLocalizations.of(context);
    final token = await _freshToken();
    if (token == null) {
      showErrorSnackBar(messenger, loc.errorSessionExpiredOpen);
      return;
    }
    messenger.showSnackBar(
        SnackBar(content: Text(loc.browserOpeningItem(item.name))));
    try {
      final path = await transfers.downloadToCache(
        downloadUrl: client.rawDownloadUri(item.path),
        token: token,
        filename: item.name,
      );
      final result = await OpenFilex.open(path);
      if (result.type == ResultType.done) return;
      showErrorSnackBar(
        messenger,
        result.type == ResultType.noAppToOpen
            ? loc.browserNoAppToOpen(item.name)
            : loc.browserCouldNotOpen(item.name, result.message),
      );
    } catch (e) {
      showErrorSnackBar(messenger, loc.browserCouldNotOpen(item.name, '$e'));
    }
  }

  /// Asks where to save a download. Shows the remembered folder — or "App
  /// storage" when none is set — and a "Change folder…" button that opens the
  /// SAF directory picker. A newly picked folder is held in local dialog state
  /// only and persisted as the new default when the user confirms with
  /// Download — tapping Cancel leaves the saved default untouched. Returns the
  /// chosen absolute directory (a null `directory` means the app's private
  /// storage), or null overall when the user cancels. Public because the
  /// browser's batch zip download shares this dialog.
  Future<({String? directory})?> chooseSaveLocation(
      BuildContext context) async {
    final loc = AppLocalizations.of(context);
    var dir = prefs.downloadDir;
    return showDialog<({String? directory})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(loc.browserSaveDownloadTo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dir ?? loc.browserAppStorageDefault,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(loc.browserChangeFolder),
                  onPressed: () async {
                    final chosen = await FilePicker.getDirectoryPath();
                    if (chosen == null) return;
                    setLocal(() => dir = chosen);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(loc.actionCancel)),
            FilledButton(
                onPressed: () async {
                  // Persist the (possibly changed) folder only on confirm.
                  if (dir != prefs.downloadDir) await prefs.setDownloadDir(dir);
                  if (ctx.mounted) Navigator.pop(ctx, (directory: dir));
                },
                child: Text(loc.actionDownload)),
          ],
        ),
      ),
    );
  }

  // --- share -------------------------------------------------------------------

  /// Creates a public share link for [item] (single file or folder), surfacing
  /// the resulting URL in a copyable / shareable dialog. Errors are copyable.
  /// Returns true when a share was created.
  Future<bool> shareLink(BuildContext context, FbResource item) =>
      showCreateShareDialog(context, client: client, item: item);

  /// Offers the two share methods for [items] — a server share link or sending
  /// local copies through the system share sheet — and runs the chosen one.
  /// Availability comes from the pure [shareOptionsFor]; unavailable methods
  /// stay visible but disabled, with the reason as their subtitle.
  Future<void> showShareChooser(
      BuildContext context, List<FbResource> items) async {
    if (items.isEmpty) return;
    final options = shareOptionsFor(items);
    final method = await showModalBottomSheet<_ShareMethod>(
      context: context,
      builder: (sheetCtx) {
        final loc = AppLocalizations.of(sheetCtx);
        final single = items.length == 1;
        // Scrollable so the sheet degrades gracefully on short/landscape
        // screens instead of overflowing its height cap.
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(single
                      ? (items.single.isDir
                          ? Icons.folder
                          : Icons.insert_drive_file)
                      : Icons.checklist),
                  title: Text(
                      single
                          ? items.single.name
                          : loc.browserSelectedCount(items.length),
                      overflow: TextOverflow.ellipsis),
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: options.canSendFiles,
                  leading: const Icon(Icons.share_outlined),
                  title: Text(loc.shareSendCopy(items.length)),
                  subtitle: Text(options.canSendFiles
                      ? loc.shareSendCopySubtitle
                      : loc.shareSendFoldersUnsupported),
                  onTap: () => Navigator.pop(sheetCtx, _ShareMethod.sendCopy),
                ),
                ListTile(
                  enabled: options.canShareLink,
                  leading: const Icon(Icons.link),
                  title: Text(loc.browserShareLink),
                  subtitle: Text(options.canShareLink
                      ? loc.shareLinkSubtitle
                      : loc.shareLinkSelectOne),
                  onTap: () => Navigator.pop(sheetCtx, _ShareMethod.link),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (method == null || !context.mounted) return;
    switch (method) {
      case _ShareMethod.link:
        await shareLink(context, items.single);
      case _ShareMethod.sendCopy:
        await shareNative(context, items);
    }
  }

  /// Sends local copies of [items] through the system share sheet (WhatsApp,
  /// email, …). The sheet can only hand out files that exist on the device, so
  /// each item is first fetched into the app cache — the same short-lived
  /// open-with cache, purged on next launch — then passed to `share_plus`
  /// (which ships its own Android `FileProvider`; no manifest config needed).
  /// Selections above [shareSizeWarnBytes] get a confirmation first.
  Future<void> shareNative(
      BuildContext context, List<FbResource> items) async {
    // Folders would need a server-side zip first; the UI never offers them
    // here (see [shareOptionsFor]) — this guard just keeps the API safe.
    if (items.isEmpty || items.any((item) => item.isDir)) return;
    final loc = AppLocalizations.of(context);
    final total = items.fold<int>(0, (sum, item) => sum + item.size);
    if (total > shareSizeWarnBytes) {
      final ok = await _confirmLargeSend(context, loc, total);
      if (!ok || !context.mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final token = await _freshToken();
    if (token == null) {
      showErrorSnackBar(messenger, loc.errorSessionExpiredShare);
      return;
    }
    messenger.showSnackBar(
        SnackBar(content: Text(loc.sharePreparingCount(items.length))));
    try {
      final files = <XFile>[];
      for (final item in items) {
        files.add(XFile(await transfers.downloadToCache(
          downloadUrl: client.rawDownloadUri(item.path),
          token: token,
          filename: item.name,
        )));
      }
      messenger.hideCurrentSnackBar();
      await SharePlus.instance.share(ShareParams(files: files));
    } catch (e) {
      showErrorSnackBar(messenger, loc.shareCouldNotSend('$e'));
    }
  }

  Future<bool> _confirmLargeSend(
      BuildContext context, AppLocalizations loc, int totalBytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.shareLargeTitle),
        content: Text(loc.shareLargeBody(formatBytes(totalBytes))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.actionCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.actionContinue)),
        ],
      ),
    );
    return ok ?? false;
  }

  // --- rename / delete ---------------------------------------------------------

  /// Prompts for a new name and renames [item] in place. Returns true when the
  /// server accepted the rename (callers refresh/close their view).
  Future<bool> rename(BuildContext context, FbResource item) async {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.actionRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: loc.browserNewNameLabel),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.actionCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(loc.actionRename),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == item.name) {
      return false;
    }
    if (!context.mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    final parent = p.posix.dirname(item.path);
    final dest = p.posix.join(parent == '.' ? '/' : parent, newName);
    try {
      await client.rename(item.path, dest);
      return true;
    } catch (e) {
      showErrorSnackBar(messenger, loc.browserRenameFailed('$e'));
      return false;
    }
  }

  /// Confirms and deletes [item]. Returns true when the server accepted the
  /// delete (callers refresh/close their view).
  Future<bool> delete(BuildContext context, FbResource item) async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.browserDeleteItemTitle(item.name)),
        content: Text(item.isDir
            ? loc.browserDeleteFolderWarning
            : loc.browserDeleteFileWarning),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.actionCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.actionDelete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.delete(item.path);
      return true;
    } catch (e) {
      showErrorSnackBar(messenger, loc.browserDeleteFailed('$e'));
      return false;
    }
  }

  // --- the per-item sheet --------------------------------------------------------

  /// The long-form action sheet for one resource (the tap target for files
  /// with no in-app viewer, and the search screen's file hand-off). Rename and
  /// delete appear only with modify permission, matching the selection bar.
  /// Returns true when the chosen action changed the server, so the caller can
  /// refresh its listing.
  Future<bool> showActionsSheet(BuildContext context, FbResource item) async {
    final choice = await showModalBottomSheet<_ItemAction>(
      context: context,
      builder: (sheetCtx) {
        final loc = AppLocalizations.of(sheetCtx);
        // Scrollable so the row count (which varies with permissions and item
        // type) can exceed the sheet's height cap on short screens.
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading:
                      Icon(item.isDir ? Icons.folder : Icons.insert_drive_file),
                  title: Text(item.name, overflow: TextOverflow.ellipsis),
                  subtitle: item.isDir ? null : Text(formatBytes(item.size)),
                ),
                const Divider(height: 1),
                if (!item.isDir)
                  _sheetTile(sheetCtx, Icons.open_in_new, loc.actionOpenWith,
                      _ItemAction.openWith),
                _sheetTile(
                    sheetCtx,
                    Icons.download_outlined,
                    item.isDir ? loc.browserDownloadAsZip : loc.actionDownload,
                    _ItemAction.download),
                if (!item.isDir)
                  _sheetTile(sheetCtx, Icons.share_outlined,
                      loc.shareSendCopy(1), _ItemAction.sendCopy),
                _sheetTile(sheetCtx, Icons.link, loc.browserShareLink,
                    _ItemAction.shareLink),
                if (canModify) ...[
                  _sheetTile(sheetCtx, Icons.drive_file_rename_outline,
                      loc.actionRename, _ItemAction.rename),
                  _sheetTile(sheetCtx, Icons.delete_outline, loc.actionDelete,
                      _ItemAction.delete),
                ],
                _sheetTile(sheetCtx, Icons.info_outline, loc.actionDetails,
                    _ItemAction.details),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !context.mounted) return false;
    switch (choice) {
      case _ItemAction.openWith:
        await openWith(context, item);
        return false;
      case _ItemAction.download:
        await download(context, item);
        return false;
      case _ItemAction.sendCopy:
        await shareNative(context, [item]);
        return false;
      case _ItemAction.shareLink:
        await shareLink(context, item);
        return false;
      case _ItemAction.rename:
        return rename(context, item);
      case _ItemAction.delete:
        return delete(context, item);
      case _ItemAction.details:
        await FileDetailsSheet.show(context, resource: item, client: client);
        return false;
    }
  }

  Widget _sheetTile(
          BuildContext sheetCtx, IconData icon, String label, _ItemAction action) =>
      ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: () => Navigator.pop(sheetCtx, action),
      );
}

/// How the user chose to share in [ItemActions.showShareChooser].
enum _ShareMethod { link, sendCopy }

/// Rows of [ItemActions.showActionsSheet]; the sheet pops with the picked row
/// and the sheet's caller runs the flow, so mutation results can be returned.
enum _ItemAction {
  openWith,
  download,
  sendCopy,
  shareLink,
  rename,
  delete,
  details,
}

/// App-bar overflow menu giving a viewer screen the full action sweep for the
/// resource it is showing. Details stays a separate app-bar button on the
/// viewers (metadata, not an action), so it is not duplicated here.
///
/// Mutations are reported through [onRenamed]/[onDeleted] *after* the server
/// accepted them; the hosting viewer decides what that means for itself
/// (pop, drop the page, …) and for the screen beneath it.
class ItemActionsMenu extends StatelessWidget {
  const ItemActionsMenu({
    super.key,
    required this.actions,
    required this.resource,
    this.onRenamed,
    this.onDeleted,
  });

  final ItemActions actions;
  final FbResource resource;
  final VoidCallback? onRenamed;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return PopupMenuButton<_MenuChoice>(
      tooltip: loc.browserMoreOptionsTooltip,
      onSelected: (choice) => _dispatch(context, choice),
      itemBuilder: (_) => [
        _menuItem(_MenuChoice.share, Icons.share_outlined, loc.actionShare),
        _menuItem(
            _MenuChoice.download, Icons.download_outlined, loc.actionDownload),
        if (!resource.isDir)
          _menuItem(
              _MenuChoice.openWith, Icons.open_in_new, loc.actionOpenWith),
        if (actions.canModify) ...[
          _menuItem(_MenuChoice.rename, Icons.drive_file_rename_outline,
              loc.actionRename),
          _menuItem(
              _MenuChoice.delete, Icons.delete_outline, loc.actionDelete),
        ],
      ],
    );
  }

  PopupMenuItem<_MenuChoice> _menuItem(
          _MenuChoice value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );

  Future<void> _dispatch(BuildContext context, _MenuChoice choice) async {
    switch (choice) {
      case _MenuChoice.share:
        await actions.showShareChooser(context, [resource]);
      case _MenuChoice.download:
        await actions.download(context, resource);
      case _MenuChoice.openWith:
        await actions.openWith(context, resource);
      case _MenuChoice.rename:
        if (await actions.rename(context, resource)) onRenamed?.call();
      case _MenuChoice.delete:
        if (await actions.delete(context, resource)) onDeleted?.call();
    }
  }
}

enum _MenuChoice { share, download, openWith, rename, delete }
