import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../api/filebrowser_client.dart';
import '../api/models.dart';
import 'error_display.dart';
import 'file_details_sheet.dart';

/// In-app viewer for text-like files (see [FbResource.isText]): fetches the
/// whole file and renders it as selectable monospace text.
///
/// The listed size gates the fetch — anything over [maxPreviewBytes] isn't
/// downloaded at all; the screen offers the "Open with…" hand-off instead
/// (via [onOpenExternally], which the browser wires to its open-with flow).
/// Bytes that aren't valid UTF-8 are decoded leniently (U+FFFD replacement),
/// so a mislabeled binary still renders something rather than crashing.
class TextViewerScreen extends StatefulWidget {
  const TextViewerScreen({
    super.key,
    required this.client,
    required this.resource,
    this.onOpenExternally,
  });

  final FileBrowserClient client;
  final FbResource resource;

  /// Invoked when the user chooses "Open with…" (file too large, or from the
  /// app bar); typically the browser's open-with hand-off.
  final void Function()? onOpenExternally;

  /// Preview cap: 1 MiB of text is already ~15k lines — beyond that native
  /// editors handle it better than a Flutter text span would.
  static const int maxPreviewBytes = 1024 * 1024;

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  late Future<String?> _content = _load();

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
          if (widget.onOpenExternally != null)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: loc.actionOpenWith,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenExternally!();
              },
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: loc.actionDetails,
            onPressed: () => FileDetailsSheet.show(
              context,
              resource: widget.resource,
              client: widget.client,
            ),
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
            if (widget.onOpenExternally != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onOpenExternally!();
                },
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
