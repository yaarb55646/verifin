import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../platform_bridge.dart';
import 'backup_settings.dart';

export '../platform_bridge.dart'
    show PickedBackupFile, StagedCacheFile, StreamedWriteReceipt;

/// 用户选择的备份目录：Android 上 [uri] 为 SAF 树 URI，桌面上为文件系统路径。
class PickedBackupDirectory {
  const PickedBackupDirectory({required this.uri, required this.label});

  final String uri;
  final String label;
}

Future<PickedBackupDirectory?> pickBackupDirectory() async {
  if (Platform.isAndroid) {
    final result = await AppStorageBridge.pickBackupDirectory();
    if (result == null || (result['uri'] ?? '').isEmpty) {
      return null;
    }
    return PickedBackupDirectory(
      uri: result['uri']!,
      label: result['label']!.isEmpty ? result['uri']! : result['label']!,
    );
  }
  final path = await getDirectoryPath();
  if (path == null) {
    return null;
  }
  return PickedBackupDirectory(uri: path, label: p.basename(path));
}

Future<List<BackupFileInfo>> listBackupFiles(String directoryUri) async {
  if (Platform.isAndroid) {
    final raw = await AppStorageBridge.listBackupFiles(directoryUri);
    return raw.map(BackupFileInfo.fromMap).toList();
  }
  final dir = Directory(directoryUri);
  if (!dir.existsSync()) {
    return const <BackupFileInfo>[];
  }
  final result = <BackupFileInfo>[];
  for (final entity in dir.listSync()) {
    if (entity is! File) {
      continue;
    }
    final name = p.basename(entity.path);
    if (!name.endsWith('.json') &&
        !name.endsWith('.zip') &&
        !name.endsWith('.verifin')) {
      continue;
    }
    final stat = entity.statSync();
    result.add(
      BackupFileInfo(
        uri: entity.uri.toString(),
        name: name,
        modifiedAt: stat.modified,
        sizeBytes: stat.size,
      ),
    );
  }
  return result;
}

Future<bool> deleteBackupFile(String fileUri) async {
  if (Platform.isAndroid) {
    return AppStorageBridge.deleteBackupFile(fileUri);
  }
  final file = File.fromUri(Uri.parse(fileUri));
  if (!file.existsSync()) {
    return false;
  }
  await file.delete();
  return true;
}

// ---- 大文件流式路径（不把整包放进内存）----

/// 打开备份文件选择器，只回传 URI 与元信息（不读字节）。
///
/// Android 用自带 SAF 选择器返回 `content://` URI：`file_selector` 会在原生侧把整份
/// 文件读进 `byte[]` 再复制一份，GB 级备份必然 OOM（Issue 45）。桌面继续用
/// `file_selector`（本地文件，无复制代价），返回 `file://` URI。
Future<PickedBackupFile?> pickBackupFile() async {
  if (Platform.isAndroid) {
    return AppStorageBridge.pickBackupFile();
  }
  final file = await openFile(
    acceptedTypeGroups: <XTypeGroup>[_backupTypeGroup],
  );
  if (file == null) {
    return null;
  }
  return PickedBackupFile(
    uri: Uri.file(file.path).toString(),
    name: p.basename(file.path),
    size: await file.length(),
  );
}

/// 备份文件类型过滤：zip / 旧版明文与加密信封 json / 新版加密容器 verifin。
const XTypeGroup _backupTypeGroup = XTypeGroup(
  label: 'Veri Fin backup',
  extensions: <String>['json', 'zip', 'verifin'],
  mimeTypes: <String>['application/json', 'application/zip'],
);

/// 把用户选择的备份文件流式落到应用缓存目录，返回本地路径。
///
/// 桌面本来就拿到本地文件，不做复制，并声明 `owned:false`——调用方不得删除用户原文件。
Future<StagedCacheFile?> stageBackupFileToCache(String fileUri) async {
  if (Platform.isAndroid) {
    return AppStorageBridge.stageBackupFile(fileUri);
  }
  final file = _localFileFrom(fileUri);
  if (file == null) {
    return null;
  }
  if (!file.existsSync()) {
    return null;
  }
  return StagedCacheFile(
    path: file.path,
    byteSize: file.lengthSync(),
    owned: false,
  );
}

/// 兼容传入 `file://` URI 或普通路径，解析成本地文件；其它 scheme 返回 null。
File? _localFileFrom(String uriOrPath) {
  // Windows 路径（`C:\...`）会被 Uri 解析成单字母 scheme，必须先按路径识别。
  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(uriOrPath) ||
      uriOrPath.contains('\\')) {
    return File(uriOrPath);
  }
  final uri = Uri.tryParse(uriOrPath);
  final scheme = uri?.scheme.toLowerCase() ?? '';
  if (scheme.isEmpty) {
    return File(uriOrPath);
  }
  if (scheme == 'file') {
    return File.fromUri(uri!);
  }
  return null;
}

/// 把缓存文件流式写入备份目录（同名覆盖），返回目标 URI 与写盘校验信息。
///
/// 写盘与 SHA-256 计算同一次读取完成，不再回读整份文件逐字节比对。
Future<({String uri, StreamedWriteReceipt receipt})?> writeBackupFromCacheFile({
  required String directoryUri,
  required String filename,
  required String cachePath,
  String mimeType = 'application/zip',
}) async {
  if (Platform.isAndroid) {
    return AppStorageBridge.writeBackupFromCache(
      directoryUri: directoryUri,
      filename: filename,
      cachePath: cachePath,
      mimeType: mimeType,
    );
  }
  final target = File(p.join(directoryUri, filename));
  await File(cachePath).copy(target.path);
  final length = await target.length();
  return (
    uri: target.uri.toString(),
    receipt: StreamedWriteReceipt(
      sha256: await hashFileSha256(target.path),
      byteSize: length,
    ),
  );
}

/// 把缓存文件流式写入系统下载目录；Android 10 以下与桌面返回 null，由调用方回退。
Future<StreamedWriteReceipt?> saveCacheFileToDownloadsFromCache({
  required String filename,
  required String cachePath,
  String mimeType = 'application/zip',
}) async {
  if (Platform.isAndroid) {
    return AppStorageBridge.saveCacheFileToDownloads(
      filename: filename,
      cachePath: cachePath,
      mimeType: mimeType,
    );
  }
  return null;
}

/// 删除业务缓存文件。缓存目录由应用私有目录承载，失败不阻断主流程。
Future<void> deleteCacheFile(String path) async {
  if (Platform.isAndroid) {
    await AppStorageBridge.deleteCacheFile(path);
    return;
  }
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

/// 备份解包前检查目标文件系统剩余空间；桌面端没有统一 API，返回 null 跳过预检。
Future<int?> availableBackupStorageBytes(String path) async {
  if (Platform.isAndroid) {
    return AppStorageBridge.availableBytes(path);
  }
  return null;
}

/// 分块计算文件 SHA-256（写入校验与损坏检测用），内存与文件体积无关。
Future<String> hashFileSha256(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}
