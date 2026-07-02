import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../api/filebrowser_client.dart';
import '../api/models.dart';
import '../api/share_link.dart';
import 'error_display.dart';
import 'share_dialog.dart';

/// Manage existing share links (`GET /api/shares`): one row per share with its
/// path, humanized expiry (with an expired flag), a lock icon when password
/// protected, the copyable public link, and a delete action (with confirm).
///
/// Admins see every share; normal users see their own (the server scopes the
/// list). Reachable from the Status screen.
class SharesScreen extends StatefulWidget {
  const SharesScreen({super.key, required this.client});

  final FileBrowserClient client;

  @override
  State<SharesScreen> createState() => _SharesScreenState();
}

class _SharesScreenState extends State<SharesScreen> {
  late Future<List<FbShare>> _shares;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _shares = widget.client.listShares();
  }

  void _reload() => setState(_load);

  Future<void> _delete(FbShare share) async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.sharesDeleteTitle),
        content: Text(loc.sharesDeleteBody(share.path)),
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
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.client.deleteShare(share.hash);
      _reload();
    } catch (e) {
      showErrorSnackBar(messenger, loc.sharesCouldNotDelete('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.sharesTitle)),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<FbShare>>(
          future: _shares,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return CopyableErrorView(
                  message: snap.error.toString(), onRetry: _reload);
            }
            final shares = snap.data ?? const [];
            if (shares.isEmpty) {
              final hint = Theme.of(context).colorScheme.onSurfaceVariant;
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.link_off, size: 48, color: hint),
                  const SizedBox(height: 12),
                  Center(child: Text(loc.sharesEmpty)),
                  const SizedBox(height: 6),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        loc.sharesEmptyHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: hint),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: shares.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _ShareTile(
                share: shares[i],
                baseUrl: widget.client.baseUrl,
                onDelete: () => _delete(shares[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({
    required this.share,
    required this.baseUrl,
    required this.onDelete,
  });

  final FbShare share;
  final String baseUrl;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final url = publicShareUrl(baseUrl, share.hash);
    final scheme = Theme.of(context).colorScheme;
    final expired = share.isExpired;
    return ListTile(
      isThreeLine: true,
      leading: Icon(share.hasPassword ? Icons.lock : Icons.link,
          color: expired ? scheme.error : null),
      title: Text(share.path, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            humanizeShareExpiry(share),
            style: TextStyle(
                color: expired ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: expired ? FontWeight.bold : null),
          ),
          const SizedBox(height: 2),
          Text(url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.primary)),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: loc.sharesActionsTooltip,
        onSelected: (v) {
          switch (v) {
            case 'copy':
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(loc.shareLinkCopied),
                  duration: const Duration(seconds: 2)));
            case 'share':
              Share.share(url);
            case 'open':
              showShareResultDialog(context, baseUrl: baseUrl, share: share);
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'copy',
              child: ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text(loc.sharesCopyLink))),
          PopupMenuItem(
              value: 'share',
              child: ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: Text(loc.actionShare))),
          PopupMenuItem(
              value: 'open',
              child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(loc.actionDetails))),
          PopupMenuItem(
              value: 'delete',
              child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(loc.actionDelete))),
        ],
      ),
      onTap: () =>
          showShareResultDialog(context, baseUrl: baseUrl, share: share),
    );
  }
}
