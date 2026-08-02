import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../api/filebrowser_client.dart';
import '../api/models.dart';
import 'error_display.dart';
import 'file_details_sheet.dart';
import 'item_actions.dart';

/// In-app viewer for text-like files (see [FbResource.isText]): fetches the
/// whole file and renders it as selectable monospace text.
///
/// The listed size gates the fetch — anything over [maxPreviewBytes] isn't
/// downloaded at all; the screen offers the "Open with…" hand-off instead.
/// Bytes that aren't valid UTF-8 are decoded leniently (U+FFFD replacement),
/// so a mislabeled binary still renders something rather than crashing.
class TextViewerScreen extends StatefulWidget {
  const TextViewerScreen({
    super.key,
    required this.client,
    required this.resource,
    this.actions,
    this.onChanged,
  });

  final FileBrowserClient client;
  final FbResource resource;

  /// The shared per-item flows; when present the app bar carries the full
  /// [ItemActionsMenu] (share / download / open-with / rename / delete) and
  /// the too-large state offers the open-with hand-off.
  final ItemActions? actions;

  /// Invoked after a rename/delete here changed the server, so the screen
  /// beneath (the browser) can refresh its listing.
  final VoidCallback? onChanged;

  /// Preview cap: 1 MiB of text is already ~15k lines — beyond that native
  /// editors handle it better than a Flutter text span would.
  static const int maxPreviewBytes = 1024 * 1024;

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  late Future<String?> _content = _load();

  /// The viewed file was renamed or deleted: this screen now shows stale
  /// content, so notify the browser and close. Invoked after an async flow,
  /// hence the mounted guard.
  void _closeAfterChange() {
    widget.onChanged?.call();
    if (mounted) Navigator.of(context).pop();
  }

  /// Null means "too large to preview" (never fetched).
  Future<String?> _load() async {
    if (widget.resource.size > TextViewerScreen.maxPreviewBytes) return null;
    final bytes = await widget.client.downloadBytes(widget.resource.path);
    if (bytes.length > TextViewerScreen.maxPreviewBytes) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.resource.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: loc.actionDetails,
            onPressed: () => FileDetailsSheet.show(
              context,
              resource: widget.resource,
              client: widget.client,
            ),
          ),
          if (widget.actions != null)
            ItemActionsMenu(
              actions: widget.actions!,
              resource: widget.resource,
              onRenamed: _closeAfterChange,
              onDeleted: _closeAfterChange,
            ),
        ],
      ),
      body: FutureBuilder<String?>(
        future: _content,
        builder: (context, snap) {
          if (snap.hasError) {
            return CopyableErrorView(
              message: loc.textViewerCouldNotLoad(
                  widget.resource.name, '${snap.error}'),
              onRetry: () => setState(() {
                _content = _load();
              }),
            );
          }
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final text = snap.data;
          if (text == null) return _tooLarge(context);
          if (text.isEmpty) {
            return Center(child: Text(loc.textViewerEmptyFile));
          }
          return Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tooLarge(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              loc.textViewerTooLarge(formatBytes(widget.resource.size)),
              textAlign: TextAlign.center,
            ),
            if (widget.actions != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    widget.actions!.openWith(context, widget.resource),
                icon: const Icon(Icons.open_in_new),
                label: Text(loc.actionOpenWith),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
