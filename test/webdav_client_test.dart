import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/backup/backup_progress.dart';
import 'package:verifin/app/backup/webdav_client.dart';
import 'package:verifin/app/backup/webdav_config.dart';

void main() {
  Future<HttpServer> startServer(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await handler(request);
      } catch (_) {
        // 客户端取消或超时会主动断开，连接异常由被测逻辑负责处理。
      }
    });
    addTearDown(() => server.close(force: true));
    return server;
  }

  WebdavConfig configFor(HttpServer server) {
    return WebdavConfig(
      url: 'http://127.0.0.1:${server.port}/dav/',
      username: 'user',
      password: 'secret',
    );
  }

  Future<File> temporaryFile(String prefix, int bytes) async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}',
    );
    await file.writeAsBytes(Uint8List(bytes));
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });
    return file;
  }

  test('upload can be cancelled while streaming the request body', () async {
    final server = await startServer((request) async {
      if (request.method == 'MKCOL') {
        request.response.statusCode = HttpStatus.created;
        await request.response.close();
        return;
      }
      await request.drain<void>();
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    });
    final file = await temporaryFile('verifin_upload_cancel', 2 * 1024 * 1024);
    var checks = 0;

    await expectLater(
      webdavUploadFile(
        configFor(server),
        'backup.zip',
        file.path,
        isCancelled: () {
          checks++;
          return checks > 3;
        },
      ),
      throwsA(isA<BackupCancelledException>()),
    );
    expect(checks, greaterThan(3));
  });

  test('upload fails when the server never answers PUT', () async {
    final server = await startServer((request) async {
      if (request.method == 'MKCOL') {
        request.response.statusCode = HttpStatus.created;
        await request.response.close();
        return;
      }
      await request.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    });
    final file = await temporaryFile('verifin_upload_timeout', 32);

    await expectLater(
      webdavUploadFile(
        configFor(server),
        'backup.zip',
        file.path,
        responseTimeout: const Duration(milliseconds: 50),
      ),
      throwsA(
        isA<WebdavException>().having(
          (error) => error.message,
          'message',
          contains('超时'),
        ),
      ),
    );
  });

  test(
    'download can be cancelled and removes the partial cache file',
    () async {
      final server = await startServer((request) async {
        request.response.statusCode = HttpStatus.ok;
        for (var index = 0; index < 20; index++) {
          request.response.add(Uint8List(64 * 1024));
          await request.response.flush();
        }
        await request.response.close();
      });
      final target = await temporaryFile('verifin_download_cancel', 0);
      var checks = 0;

      await expectLater(
        webdavDownloadToFile(
          configFor(server),
          '/dav/backup.zip',
          target.path,
          isCancelled: () {
            checks++;
            return checks > 2;
          },
        ),
        throwsA(isA<BackupCancelledException>()),
      );
      expect(await target.exists(), isFalse);
    },
  );

  test('download times out when the response body stalls', () async {
    final server = await startServer((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentLength = 1024;
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        request.response.add(Uint8List(1024));
        await request.response.close();
      } catch (_) {
        // 客户端超时关闭连接后服务端写入失败是预期行为。
      }
    });
    final target = await temporaryFile('verifin_download_timeout', 0);
    await target.delete();

    await expectLater(
      webdavDownloadToFile(
        configFor(server),
        '/dav/backup.zip',
        target.path,
        responseTimeout: const Duration(milliseconds: 50),
      ),
      throwsA(
        isA<WebdavException>().having(
          (error) => error.message,
          'message',
          contains('超时'),
        ),
      ),
    );
    expect(await target.exists(), isFalse);
  });
}
