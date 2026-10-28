import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_error.dart';
import 'package:verifin/app/ai/ai_model_catalog.dart';
import 'package:verifin/app/ai/ai_provider_presets.dart';
import 'package:verifin/app/ai/ai_settings.dart';

Future<AiSettings> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final pending = <Future<void>>[];
  final subscription = server.listen((request) {
    pending.add(handler(request));
  });
  addTearDown(() async {
    await subscription.cancel();
    await server.close(force: true);
    for (final future in pending) {
      try {
        await future;
      } on HttpException {
        // 客户端主动断流属于超时测试的预期收尾。
      }
    }
  });
  return AiSettings(
    providerId: customAiProviderId,
    baseUrl: 'http://${server.address.address}:${server.port}/v1',
    model: 'test-model',
  );
}

AiSettings _settings(AiSettings settings, {String apiKey = ''}) =>
    settings.copyWith(apiKey: apiKey);

void main() {
  test('解析 data[].id 并排序去重', () {
    final models = parseAiModelList(<String, Object?>{
      'data': <Object?>[
        <String, Object?>{'id': 'z-model', 'owned_by': 'vendor'},
        <String, Object?>{'id': 'vendor-b/A-model'},
        <String, Object?>{'id': 'z-model', 'owned_by': 'duplicate'},
        <String, Object?>{'id': ''},
        <String, Object?>{'id': 42},
      ],
      'models': <Object?>[
        <String, Object?>{'slug': 'should-be-ignored'},
      ],
    });

    expect(models.map((model) => model.id), <String>[
      'vendor-b/A-model',
      'z-model',
    ]);
    expect(models.last.ownedBy, 'vendor');
    expect(models.first.ownedBy, 'vendor-b');
  });

  test('解析 models[].slug 与 id', () {
    final models = parseAiModelList(<String, Object?>{
      'models': <Object?>[
        <String, Object?>{'slug': 'glm-a'},
        <String, Object?>{'id': 'glm-b'},
        <String, Object?>{'slug': 1, 'id': 'glm-c'},
        <String, Object?>{'name': 'ignored'},
      ],
    });

    expect(models.map((model) => model.id), <String>[
      'glm-a',
      'glm-b',
      'glm-c',
    ]);
  });

  test('非法模型列表抛 badResponse', () {
    for (final value in <Object?>[
      null,
      <Object?>[],
      <String, Object?>{},
      <String, Object?>{'data': 'bad'},
    ]) {
      expect(
        () => parseAiModelList(value),
        throwsA(
          isA<AiException>().having(
            (error) => error.code,
            'code',
            AiErrorCode.badResponse,
          ),
        ),
      );
    }
  });

  test('空 Key 不发送 Authorization，公开列表可用', () async {
    final settings = await _serve((request) async {
      expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 'public-model'},
          ],
        }),
      );
      await request.response.close();
    });

    final models = await fetchAiModels(
      settings: _settings(settings),
      provider: customAiProviderPreset,
    );
    expect(models.single.id, 'public-model');
  });

  test('非空 Key 使用 Bearer 鉴权', () async {
    final settings = await _serve((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer secret',
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 'private-model'},
          ],
        }),
      );
      await request.response.close();
    });

    final models = await fetchAiModels(
      settings: _settings(settings, apiKey: 'secret'),
      provider: customAiProviderPreset,
    );
    expect(models.single.id, 'private-model');
  });

  test('404 映射为渠道不支持模型列表', () async {
    final settings = await _serve((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    await expectLater(
      fetchAiModels(
        settings: _settings(settings),
        provider: customAiProviderPreset,
      ),
      throwsA(
        isA<AiException>().having(
          (error) => error.code,
          'code',
          AiErrorCode.modelListUnsupported,
        ),
      ),
    );
  });

  test('非 JSON 映射为 badResponse', () async {
    final settings = await _serve((request) async {
      request.response.write('<html>not json</html>');
      await request.response.close();
    });

    await expectLater(
      fetchAiModels(
        settings: _settings(settings),
        provider: customAiProviderPreset,
      ),
      throwsA(
        isA<AiException>().having(
          (error) => error.code,
          'code',
          AiErrorCode.badResponse,
        ),
      ),
    );
  });

  test('同源重定向可用，跨域重定向被拒绝', () async {
    final settings = await _serve((request) async {
      if (request.uri.path.endsWith('/models')) {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/v1/final-models',
        );
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{'id': 'redirected-model'},
            ],
          }),
        );
      }
      await request.response.close();
    });
    final models = await fetchAiModels(
      settings: _settings(settings),
      provider: customAiProviderPreset,
    );
    expect(models.single.id, 'redirected-model');

    var foreignHit = false;
    final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => foreign.close(force: true));
    foreign.listen((request) async {
      foreignHit = true;
      request.response.write('{}');
      await request.response.close();
    });
    final redirecting = await _serve((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://${foreign.address.address}:${foreign.port}/models',
      );
      await request.response.close();
    });

    await expectLater(
      fetchAiModels(
        settings: _settings(redirecting),
        provider: customAiProviderPreset,
      ),
      throwsA(
        isA<AiException>().having(
          (error) => error.code,
          'code',
          AiErrorCode.badUrl,
        ),
      ),
    );
    expect(foreignHit, isFalse);
  });

  test('超时映射为 timeout', () async {
    final settings = await _serve((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      request.response.write('{}');
      await request.response.close();
    });

    await expectLater(
      fetchAiModels(
        settings: _settings(settings),
        provider: customAiProviderPreset,
        timeout: const Duration(milliseconds: 30),
      ),
      throwsA(
        isA<AiException>().having(
          (error) => error.code,
          'code',
          AiErrorCode.timeout,
        ),
      ),
    );
  });
}
