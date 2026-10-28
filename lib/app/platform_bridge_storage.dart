part of 'platform_bridge.dart';

/// 原生流式复制到缓存后的结果：本地路径 + 字节数 + 归属。
class StagedCacheFile {
  const StagedCacheFile({
    required this.path,
    required this.byteSize,
    this.owned = true,
  });

  final String path;
  final int byteSize;

  /// true 表示这个文件是本应用为本次操作**新建**的临时副本，用完必须删除；
  /// false 表示它本来就是用户自己的文件，调用方不得删除。
  final bool owned;
}

/// 用户挑中的备份文件描述（只含 URI 与元信息，不含字节）。
class PickedBackupFile {
  const PickedBackupFile({required this.uri, this.name, this.size});

  /// Android 为 SAF `content://` URI；桌面为 `file://` URI。
  final String uri;

  /// 原始文件名，仅用于提示；读取失败时为 null。
  final String? name;

  /// 文件大小（字节），未知为 null。
  final int? size;
}

/// 原生流式写出后的回执：写入字节数与内容 SHA-256（写盘时同步算出）。
class StreamedWriteReceipt {
  const StreamedWriteReceipt({required this.sha256, required this.byteSize});

  final String sha256;
  final int byteSize;
}

/// 文件存储：系统下载目录写出（CSV 模板 / zip 导出）与备份目录 SAF 读写。
class AppStorageBridge {
  AppStorageBridge._();

  static Future<bool> saveTextToDownloads({
    required String filename,
    required String content,
    required String mimeType,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('saveTextToDownloads', {
            'filename': filename,
            'content': content,
            'mimeType': mimeType,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '导出失败，请稍后再试。');
    }
  }

  /// 向下载目录写入字节文件（zip 导出）。Android 10+ 成功返回 true；更低版本或
  /// 无插件返回 false，由调用方回退到系统「保存到」选择器。
  static Future<bool> saveBytesToDownloads({
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('saveBytesToDownloads', {
            'filename': filename,
            'bytes': bytes,
            'mimeType': mimeType,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '导出失败，请稍后再试。');
    }
  }

  /// 通过系统文档树选择器（SAF）让用户选择备份目录，返回持久化的树 URI 与可读名称。
  /// 用户取消时返回 null。
  static Future<Map<String, String>?> pickBackupDirectory() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pickBackupDirectory',
      );
      if (result == null) {
        return null;
      }
      return <String, String>{
        'uri': result['uri'] as String? ?? '',
        'label': result['label'] as String? ?? '',
      };
    } on MissingPluginException {
      throw Exception('当前平台不支持选择备份目录。');
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '选择备份目录失败，请稍后再试。');
    }
  }

  /// 列出备份目录内的文件元数据。
  static Future<List<Map<Object?, Object?>>> listBackupFiles(
    String directoryUri,
  ) async {
    try {
      final result = await _channel.invokeListMethod<Object?>(
        'listBackupFiles',
        <String, Object?>{'directoryUri': directoryUri},
      );
      return (result ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .toList();
    } on MissingPluginException {
      return const <Map<Object?, Object?>>[];
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '读取备份目录失败，请稍后再试。');
    }
  }

  /// 删除备份目录内某个文件。
  static Future<bool> deleteBackupFile(String fileUri) async {
    try {
      return await _channel.invokeMethod<bool>('deleteBackupFile', {
            'fileUri': fileUri,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '删除备份文件失败，请稍后再试。');
    }
  }

  // ---- 大文件流式复制（不把整包放进内存）----

  /// 打开系统文件选择器挑一个备份文件，只回传 URI 与元信息。
  ///
  /// 故意不经过 `file_selector`：该插件会把整份文件读进 Java `byte[]` 并再复制一份，
  /// GB 级备份会直接 OOM（Issue 45）。这里拿到 `content://` URI 后由
  /// [stageBackupFile] 流式复制。
  static Future<PickedBackupFile?> pickBackupFile() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pickBackupFile',
      );
      if (result == null) {
        return null;
      }
      final uri = result['uri'] as String? ?? '';
      if (uri.isEmpty) {
        return null;
      }
      final name = result['name'] as String?;
      return PickedBackupFile(
        uri: uri,
        name: name == null || name.isEmpty ? null : name,
        size: (result['size'] as num?)?.toInt(),
      );
    } on MissingPluginException {
      throw Exception('当前平台不支持选择备份文件。');
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '选择备份文件失败，请稍后再试。');
    }
  }

  /// 把用户选择的 SAF 文件流式复制到应用缓存目录，返回本地路径与字节数。
  static Future<StagedCacheFile?> stageBackupFile(String fileUri) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'stageBackupFile',
        <String, Object?>{'fileUri': fileUri},
      );
      if (result == null) {
        return null;
      }
      final path = result['path'] as String?;
      if (path == null || path.isEmpty) {
        return null;
      }
      return StagedCacheFile(
        path: path,
        byteSize: (result['bytes'] as num?)?.toInt() ?? 0,
        owned: result['owned'] as bool? ?? true,
      );
    } on MissingPluginException {
      throw Exception('当前平台不支持读取备份文件。');
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '读取备份文件失败，请稍后再试。');
    }
  }

  /// 把缓存文件流式写入备份目录（同名覆盖），返回目标 URI 与写盘校验信息。
  static Future<({String uri, StreamedWriteReceipt receipt})?>
  writeBackupFromCache({
    required String directoryUri,
    required String filename,
    required String cachePath,
    String mimeType = 'application/zip',
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'writeBackupFromCache',
        <String, Object?>{
          'directoryUri': directoryUri,
          'filename': filename,
          'cachePath': cachePath,
          'mimeType': mimeType,
        },
      );
      if (result == null) {
        return null;
      }
      final uri = result['uri'] as String? ?? '';
      return (
        uri: uri,
        receipt: StreamedWriteReceipt(
          sha256: result['sha256'] as String? ?? '',
          byteSize: (result['bytes'] as num?)?.toInt() ?? 0,
        ),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '写入备份失败，请稍后再试。');
    }
  }

  /// 把缓存文件流式写入系统下载目录；Android 10 以下返回 null（调用方回退到选择器）。
  static Future<StreamedWriteReceipt?> saveCacheFileToDownloads({
    required String filename,
    required String cachePath,
    String mimeType = 'application/zip',
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'saveCacheFileToDownloads',
        <String, Object?>{
          'filename': filename,
          'cachePath': cachePath,
          'mimeType': mimeType,
        },
      );
      if (result == null) {
        return null;
      }
      return StreamedWriteReceipt(
        sha256: result['sha256'] as String? ?? '',
        byteSize: (result['bytes'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? '导出失败，请稍后再试。');
    }
  }

  /// 删除应用缓存目录里的临时文件（备份/恢复收尾，尽力而为）。
  static Future<bool> deleteCacheFile(String path) async {
    try {
      return await _channel.invokeMethod<bool>(
            'deleteCacheFile',
            <String, Object?>{'path': path},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 返回 [path] 所在文件系统的可用字节数；平台不支持时返回 null。
  static Future<int?> availableBytes(String path) async {
    try {
      return await _channel.invokeMethod<int>('availableBytes', {'path': path});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
