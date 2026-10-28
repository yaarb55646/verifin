import 'webdav_config.dart';

/// WebDAV 操作异常，面向用户可读。
class WebdavException implements Exception {
  const WebdavException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> webdavTestConnection(WebdavConfig config) async {
  throw const WebdavException('当前平台不支持 WebDAV');
}

Future<List<WebdavRemoteFile>> webdavList(WebdavConfig config) async {
  throw const WebdavException('当前平台不支持 WebDAV');
}

Future<void> webdavDelete(WebdavConfig config, String href) async {
  throw const WebdavException('当前平台不支持 WebDAV');
}

Future<void> webdavUploadFile(
  WebdavConfig config,
  String filename,
  String cachePath, {
  bool Function()? isCancelled,
  Duration responseTimeout = const Duration(seconds: 60),
}) async {
  throw const WebdavException('当前平台不支持 WebDAV');
}

Future<void> webdavDownloadToFile(
  WebdavConfig config,
  String href,
  String cachePath, {
  bool Function()? isCancelled,
  Duration responseTimeout = const Duration(seconds: 60),
}) async {
  throw const WebdavException('当前平台不支持 WebDAV');
}
