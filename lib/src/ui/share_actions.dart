import '../api/models.dart';

/// Pure decision logic for the share entry points (the selection bar's share
/// button, the per-item action sheet, and the viewer menus): given the items
/// being shared, which methods the chooser can offer. Widget-free so the rules
/// are unit-testable (see `test/share_actions_test.dart`).

/// Total selection size above which [ItemActions.shareNative] asks for
/// confirmation first. The system share sheet needs local files, so sending
/// means downloading every item to the device cache before the sheet opens —
/// worth a heads-up beyond this size, silent below it.
const int shareSizeWarnBytes = 100 * 1024 * 1024;

/// Which share methods are available for a set of items, and what sending
/// them would cost in bytes.
class ShareOptions {
  const ShareOptions({
    required this.canShareLink,
    required this.canSendFiles,
    required this.totalSendBytes,
  });

  /// Server share links are created per path (`POST /api/share` takes one),
  /// so a link can be offered only for a single selected item. Folders are
  /// fine — quantum serves a browsable share page for them.
  final bool canShareLink;

  /// Sending a copy through the system share sheet requires local files, so
  /// it is offered when there is at least one item and none is a folder.
  /// (A folder would need a server-side zip first — not offered today.)
  final bool canSendFiles;

  /// Sum of the item sizes when [canSendFiles]; what [shareSizeWarnBytes]
  /// is compared against. Zero when sending is unavailable.
  final int totalSendBytes;
}

ShareOptions shareOptionsFor(List<FbResource> items) {
  final allFiles = items.isNotEmpty && items.every((item) => !item.isDir);
  return ShareOptions(
    canShareLink: items.length == 1,
    canSendFiles: allFiles,
    totalSendBytes:
        allFiles ? items.fold(0, (sum, item) => sum + item.size) : 0,
  );
}
