import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../api/filebrowser_client.dart';
import '../api/models.dart';
import 'error_display.dart';
import 'file_details_sheet.dart';
import 'item_actions.dart';

/// Streams a video from the server (Range-enabled download endpoint) with native
/// controls. Auth is passed via the `Authorization: Bearer` HTTP header.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.url,
    required this.headers,
    required this.title,
    this.resource,
    this.client,
    this.actions,
    this.onChanged,
  });

  final Uri url;
  final Map<String, String> headers;
  final String title;

  /// The file behind this stream; when supplied (together with [client]) an
  /// "Info" action exposes its [FileDetailsSheet].
  final FbResource? resource;
  final FileBrowserClient? client;

  /// The shared per-item flows; when supplied (together with [resource]) the
  /// app bar carries the full [ItemActionsMenu].
  final ItemActions? actions;

  /// Invoked after a rename/delete here changed the server, so the screen
  /// beneath (the browser) can refresh its listing.
  final VoidCallback? onChanged;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final video =
          VideoPlayerController.networkUrl(widget.url, httpHeaders: widget.headers);
      await video.initialize();
      if (!mounted) {
        await video.dispose();
        return;
      }
      setState(() {
        _video = video;
        _chewie = ChewieController(
          videoPlayerController: video,
          autoPlay: true,
          looping: false,
          aspectRatio: video.value.aspectRatio,
          allowFullScreen: true,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  /// The playing file was renamed or deleted: the stream URL is now stale, so
  /// notify the browser and close. Invoked after an async flow, hence the
  /// mounted guard.
  void _closeAfterChange() {
    widget.onChanged?.call();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.resource != null && widget.client != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: loc.actionDetails,
              onPressed: () => FileDetailsSheet.show(
                context,
                resource: widget.resource!,
                client: widget.client!,
              ),
            ),
          if (widget.resource != null && widget.actions != null)
            ItemActionsMenu(
              actions: widget.actions!,
              resource: widget.resource!,
              onRenamed: _closeAfterChange,
              onDeleted: _closeAfterChange,
            ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(loc.videoCouldNotPlay(_error!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => copyErrorToClipboard(
                        loc.videoCouldNotPlay(_error!),
                        ScaffoldMessenger.of(context),
                      ),
                      icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
                      label: Text(loc.actionCopy,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              )
            : _chewie != null
                ? Chewie(controller: _chewie!)
                : const CircularProgressIndicator(),
      ),
    );
  }
}
