import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/filebrowser_client.dart';
import 'chunked_upload_task.dart';
import 'transfer_record.dart';

/// Maps a user-chosen public directory path (from the SAF directory picker) to
/// a sub-directory *within* the platform's shared "Downloads" collection, so a
/// chosen-folder download can be relocated there via MediaStore instead of
/// writing to an arbitrary absolute path (which scoped storage denies on
/// Android 11+ without `MANAGE_EXTERNAL_STORAGE`).
///
/// A path already under a `Download`/`Downloads` root yields the portion after
/// that segment (e.g. `…/Download/Trips/2024` -> `Trips/2024`, `…/Download` ->
/// `''`). Any other location nests under the chosen folder's own name so files
/// still land grouped, rather than spilling into the Downloads root.
String sharedDownloadsSubdir(String absoluteDir) {
  final segs = p.split(absoluteDir).where((s) => s.isNotEmpty && s != '/').toList();
  final idx = segs.lastIndexWhere(
      (s) => s.toLowerCase() == 'download' || s.toLowerCase() == 'downloads');
  if (idx >= 0) return segs.sublist(idx + 1).join('/');
  return segs.isNotEmpty ? segs.last : '';
}

/// Runs the app's transfers over two engines and folds both into one live
/// list of [TransferRecord]s (via [records]) for the transfers screen and the
/// app-bar badge:
///
///  - `background_downloader` tasks — downloads, and uploads at or below
///    [defaultUploadChunkSize]. These run in a native foreground service and
///    survive the app being backgrounded or closed, but an upload is a single
///    POST of the raw bytes and restarts from scratch when interrupted.
///  - [ChunkedUploadTask]s — uploads above [defaultUploadChunkSize], sent as
///    sequential offset chunks (quantum's resumable scheme). These can pause/
///    resume mid-file and retry transient failures by themselves, but run in
///    the app process, so they need the app alive.
///
/// [upload] picks the engine by file size; the actions ([pause], [resume],
/// [cancel], [retry]) dispatch on the record's concrete type.
///
/// Server specifics:
///  - Download:       GET `/api/resources/download?source=…&file=…` with the
///                    `Authorization: Bearer` header.
///  - Upload:         POST `/api/resources?path=…&source=…&override=…` with
///                    the raw file bytes as the body (binary, not multipart).
///  - Chunked upload: the same POST with `X-File-Chunk-Offset` /
///                    `X-File-Total-Size` headers per chunk — see
///                    [FileBrowserClient.uploadChunk].
class TransferService {
  static const _group = 'filebrowser';
  // A separate, untracked group for the short-lived open-with cache fetch, so
  // it neither shows up in the transfers list nor is persisted by trackTasks.
  static const _openGroup = 'filebrowser_open';
  // Sub-directory of the temporary cache holding open-with downloads. Isolating
  // them in their own dir lets us purge only our files (see [_purgeOpenCache]),
  // never other plugins' temp data.
  static const _openDir = 'open_with';

  final Map<String, TransferRecord> _records = {};
  final StreamController<List<TransferRecord>> _recordsController =
      StreamController<List<TransferRecord>>.broadcast();
  StreamSubscription<TaskUpdate>? _updatesSub;

  // Live chunked-upload engines by record id, with the subscription that folds
  // each one's snapshots into [_records]. Entries leave the maps when the
  // record leaves the list (clearFinished/purgeAll).
  final Map<String, ChunkedUploadTask> _chunkedTasks = {};
  final Map<String, StreamSubscription<ChunkedUploadRecord>> _chunkedSubs = {};
  int _chunkedSeq = 0;

  // taskId -> shared-Downloads sub-directory for downloads bound for a chosen
  // public folder. The file is fetched into app storage and relocated there on
  // completion (see [download] / [_ingest]).
  final Map<String, String> _sharedTargets = {};

  Future<void> init() async {
    // configureNotification is synchronous and fluent (returns FileDownloader).
    FileDownloader().configureNotification(
      running: const TaskNotification('Transferring', '{filename}'),
      complete: const TaskNotification('Done', '{filename}'),
      error: const TaskNotification('Failed', '{filename}'),
      progressBar: true,
    );
    // Fold every status/progress update into the in-memory record map so the
    // UI sees a single, merged view per task.
    _updatesSub = FileDownloader().updates.listen(_ingest);
    // Persist task records so progress/state survives process death.
    await FileDownloader().trackTasks();
    // Open-with cache files handed to other apps are never individually
    // deleted (the receiving app may still be reading them). Purge last
    // session's leftovers on startup so they can't accumulate unbounded.
    await _purgeOpenCache();
  }

  void _ingest(TaskUpdate update) {
    final id = update.task.taskId;
    final prev = _records[id];
    _records[id] =
        applyTaskUpdate(prev is TaskTransferRecord ? prev : null, update);
    _emit();
    // A chosen-folder download finished in app storage: relocate it into the
    // shared Downloads collection (MediaStore), which needs no storage
    // permission on modern Android.
    if (update is TaskStatusUpdate &&
        update.status == TaskStatus.complete &&
        _sharedTargets.containsKey(id)) {
      final subdir = _sharedTargets.remove(id)!;
      final task = update.task;
      if (task is DownloadTask) {
        unawaited(_relocateToDownloads(task, subdir));
      }
    }
  }

  Future<void> _relocateToDownloads(DownloadTask task, String subdir) async {
    try {
      await FileDownloader().moveToSharedStorage(
        task,
        SharedStorage.downloads,
        directory: subdir,
      );
    } catch (_) {
      // Best-effort: if the move fails the file simply remains in app storage.
    }
  }

  void _emit() {
    if (!_recordsController.isClosed) {
      _recordsController.add(current);
    }
  }

  /// Live, broadcast view of every tracked transfer (most-recently-updated
  /// first), re-emitted on each status/progress change.
  Stream<List<TransferRecord>> get records => _recordsController.stream;

  /// Current snapshot of tracked transfers, active ones first.
  List<TransferRecord> get current {
    final list = _records.values.toList();
    list.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return 0;
    });
    return list;
  }

  /// Enqueue a background download of [downloadUrl].
  ///
  /// The file is always fetched into the app's own documents dir first. With no
  /// [directory] it stays there. When [directory] is the chosen public
  /// save-location (product item 13), the task is registered in [_sharedTargets]
  /// and, on completion, relocated into the platform's shared "Downloads"
  /// collection via [FileDownloader.moveToSharedStorage] (see [_ingest]).
  ///
  /// Relocating through MediaStore — rather than writing straight to the picked
  /// absolute path — is what makes this work on Android 11+ scoped storage,
  /// where direct writes outside the app sandbox are denied and the app holds no
  /// `WRITE_EXTERNAL_STORAGE`/`MANAGE_EXTERNAL_STORAGE`. The chosen path maps to
  /// a Downloads sub-directory via [sharedDownloadsSubdir]. (Device-only
  /// behaviour; not exercised by unit tests.)
  Future<String> download({
    required Uri downloadUrl,
    required String token,
    required String filename,
    String? directory,
  }) async {
    final task = DownloadTask(
      url: downloadUrl.toString(),
      // Strip any path segments from the server-supplied name so a hostile
      // server can't steer the write outside the target dir via `../`.
      filename: p.basename(filename),
      baseDirectory: BaseDirectory.applicationDocuments,
      headers: {'Authorization': 'Bearer $token'},
      group: _group,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
    );
    if (directory != null && directory.isNotEmpty) {
      _sharedTargets[task.taskId] = sharedDownloadsSubdir(directory);
    }
    await FileDownloader().enqueue(task);
    return task.taskId;
  }

  /// Foreground-downloads [downloadUrl] into the app's temporary cache and
  /// returns the resulting absolute file path once complete, for handing to a
  /// native app via open-with (product item 12). Unlike [download] this awaits
  /// completion and stays out of the tracked transfers list (its own group, no
  /// progress folding). Throws if the download does not complete.
  Future<String> downloadToCache({
    required Uri downloadUrl,
    required String token,
    required String filename,
  }) async {
    final task = DownloadTask(
      url: downloadUrl.toString(),
      filename: p.basename(filename),
      headers: {'Authorization': 'Bearer $token'},
      baseDirectory: BaseDirectory.temporary,
      directory: _openDir,
      group: _openGroup,
      updates: Updates.status,
      retries: 1,
    );
    final result = await FileDownloader().download(task);
    if (result.status != TaskStatus.complete) {
      throw Exception('Download failed (${result.status.name})');
    }
    return task.filePath();
  }

  /// Enqueue an upload of [localFilePath] to [remotePath] on [client]'s
  /// current source, picking the engine by size: files above the chunk size
  /// go through the resumable [ChunkedUploadTask]; smaller ones as a single
  /// background binary POST (which also keeps running when the app is closed).
  /// [token] authenticates the single-POST path; the chunked path rides
  /// [client]'s own token handling.
  Future<String> upload({
    required FileBrowserClient client,
    required String remotePath,
    required String localFilePath,
    required String token,
    bool override = false,
  }) async {
    final size = await File(localFilePath).length();
    if (size > defaultUploadChunkSize) {
      return _uploadChunked(
        client: client,
        remotePath: remotePath,
        localFilePath: localFilePath,
        override: override,
      );
    }
    // UploadTask locates the source file via baseDirectory + directory +
    // filename, so split the absolute path the file picker gave us.
    final (baseDirectory, directory, filename) =
        await Task.split(filePath: localFilePath);
    final task = UploadTask(
      url: client.uploadUri(remotePath, override: override).toString(),
      filename: filename,
      directory: directory,
      baseDirectory: baseDirectory,
      httpRequestMethod: 'POST',
      post: 'binary', // raw bytes in the body, as File Browser expects
      headers: {'Authorization': 'Bearer $token'},
      group: _group,
      updates: Updates.statusAndProgress,
      retries: 3,
    );
    await FileDownloader().enqueue(task);
    return task.taskId;
  }

  String _uploadChunked({
    required FileBrowserClient client,
    required String remotePath,
    required String localFilePath,
    required bool override,
  }) {
    final id = 'chunked-${_chunkedSeq++}-${DateTime.now().microsecondsSinceEpoch}';
    final task = ChunkedUploadTask(
      client: client,
      remotePath: remotePath,
      localFilePath: localFilePath,
      id: id,
      override: override,
    );
    _chunkedTasks[id] = task;
    _chunkedSubs[id] = task.updates.listen((record) {
      _records[record.id] = record;
      _emit();
    });
    _records[id] = task.snapshot;
    _emit();
    unawaited(task.start());
    return id;
  }

  /// Pause a running transfer: a pausable download in `background_downloader`,
  /// or a chunked upload (graceful, resumable pause). Single-POST uploads
  /// cannot pause — the UI hides the control via [TransferRecord.canPause].
  Future<bool> pause(TransferRecord record) async {
    switch (record) {
      case TaskTransferRecord(:final task):
        if (task is! DownloadTask) return false;
        return FileDownloader().pause(task);
      case ChunkedUploadRecord():
        final task = _chunkedTasks[record.id];
        if (task == null) return false;
        await task.pause();
        return true;
    }
  }

  /// Resume a paused transfer (see [pause]).
  Future<bool> resume(TransferRecord record) async {
    switch (record) {
      case TaskTransferRecord(:final task):
        if (task is! DownloadTask) return false;
        return FileDownloader().resume(task);
      case ChunkedUploadRecord():
        final task = _chunkedTasks[record.id];
        if (task == null) return false;
        unawaited(task.resume());
        return true;
    }
  }

  /// Cancel a transfer (any state); the record settles to `canceled`.
  Future<bool> cancel(TransferRecord record) async {
    switch (record) {
      case TaskTransferRecord():
        return FileDownloader().cancelTaskWithId(record.id);
      case ChunkedUploadRecord():
        final task = _chunkedTasks[record.id];
        if (task == null) return false;
        task.cancel();
        return true;
    }
  }

  /// Restart a failed/canceled transfer. A background task is re-enqueued
  /// with its auth header refreshed from [token] (the original task object is
  /// reused — mutable header map — so its notification and identity are
  /// preserved); a chunked upload restarts from offset 0 and authenticates
  /// through its client, so [token] is not needed there.
  Future<String> retry(TransferRecord record, {required String token}) async {
    switch (record) {
      case TaskTransferRecord(:final task):
        task.headers['Authorization'] = 'Bearer $token';
        await FileDownloader().enqueue(task);
        return task.taskId;
      case ChunkedUploadRecord():
        final task = _chunkedTasks[record.id];
        if (task != null) unawaited(task.start());
        return record.id;
    }
  }

  /// Drop finished (complete/failed/canceled) records from the in-memory list,
  /// e.g. when the user clears the transfers screen. Active transfers are kept.
  /// Finished chunked engines are disposed with their records (a cleared
  /// record can no longer be retried, so the engine has no further use).
  void clearFinished() {
    _records.removeWhere((_, r) => !r.isActive);
    _pruneChunked((id) => !_records.containsKey(id));
    _emit();
  }

  /// Dispose and forget chunked engines whose id matches [gone].
  void _pruneChunked(bool Function(String id) gone) {
    final ids = _chunkedTasks.keys.where(gone).toList();
    for (final id in ids) {
      _chunkedSubs.remove(id)?.cancel();
      _chunkedTasks.remove(id)?.dispose();
    }
  }

  /// Wipe all transfer state — for "sign out & forget". Cancels every active
  /// task in both groups, deletes the persisted task-record database (whose
  /// records carry `Authorization: Bearer` headers), clears the in-memory
  /// view, and purges the open-with cache. After this no token or downloaded
  /// byte from the old session remains on disk.
  Future<void> purgeAll() async {
    for (final task in _chunkedTasks.values) {
      task.cancel();
    }
    _pruneChunked((_) => true);
    for (final group in const [_group, _openGroup]) {
      await FileDownloader().reset(group: group);
    }
    await FileDownloader().database.deleteAllRecords();
    _records.clear();
    _emit();
    await _purgeOpenCache();
  }

  /// Delete the open-with cache sub-directory and everything in it.
  Future<void> _purgeOpenCache() async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory(p.join(tmp.path, _openDir));
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup; a failure here is not user-visible.
    }
  }

  /// Stream of raw progress/status updates (retained for back-compat).
  Stream<TaskUpdate> get updates => FileDownloader().updates;

  void dispose() {
    _updatesSub?.cancel();
    _pruneChunked((_) => true);
    _recordsController.close();
  }
}
