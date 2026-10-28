import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ai_error.dart';
import 'ai_provider_presets.dart';
import 'ai_settings.dart';

const int _maxModelResponseBytes = 5 * 1024 * 1024;
const int _maxModelCount = 2000;
const int _maxRedirects = 3;

/// 渠道模型列表中的一个稳定模型标识。
class AiModelInfo {
  const AiModelInfo({required this.id, this.ownedBy});

  final String id;
  final String? ownedBy;

  @override
  bool operator ==(Object other) =>
      other is AiModelInfo && other.id == id && other.ownedBy == ownedBy;

  @override
  int get hashCode => Object.hash(id, ownedBy);
}

/// 获取渠道当前可用模型。
///
/// 该请求只携带 API Key 与固定请求头，不发送任何账目、聊天或日志数据。
Future<List<AiModelInfo>> fetchAiModels({
  required AiSettings settings,
  required AiProviderPreset provider,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final rawUrl = aiModelListUrlFor(
    provider: provider,
    baseUrl: settings.baseUrl,
    modelListUrl: settings.modelListUrl,
  );
  if (rawUrl.isEmpty) {
    throw AiException(AiErrorCode.badUrl, detail: 'empty model list url');
  }
  final uri = Uri.tryParse(rawUrl);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw AiException(AiErrorCode.badUrl, detail: 'invalid model list url');
  }

  final client = HttpClient()..connectionTimeout = timeout;
  try {
    var current = uri;
    HttpClientResponse? response;
    for (var redirect = 0; redirect <= _maxRedirects; redirect += 1) {
      final request = await client.getUrl(current).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final apiKey = settings.apiKey.trim();
      if (apiKey.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      response = await request.close().timeout(timeout);

      if (!_isRedirect(response.statusCode)) {
        break;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.trim().isEmpty) {
        throw AiException(
          AiErrorCode.badUrl,
          detail: 'redirect without target',
        );
      }
      final next = current.resolve(location.trim());
      if (!_sameOrigin(current, next)) {
        throw AiException(
          AiErrorCode.badUrl,
          detail: 'cross-origin model list redirect rejected',
        );
      }
      await response.drain<void>();
      current = next;
    }

    if (response == null) {
      throw AiException(AiErrorCode.badUrl, detail: 'missing response');
    }
    if (_isRedirect(response.statusCode)) {
      throw AiException(AiErrorCode.badUrl, detail: 'too many redirects');
    }
    final status = response.statusCode;
    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      throw AiException(AiErrorCode.authFailed, detail: 'HTTP $status');
    }
    if (status == HttpStatus.notFound ||
        status == HttpStatus.methodNotAllowed) {
      throw AiException(
        AiErrorCode.modelListUnsupported,
        detail: 'HTTP $status',
      );
    }
    if (status == HttpStatus.tooManyRequests) {
      throw AiException(AiErrorCode.rateLimited, detail: 'HTTP $status');
    }
    if (status >= HttpStatus.badRequest &&
        status < HttpStatus.internalServerError) {
      throw AiException(AiErrorCode.upstream, detail: 'HTTP $status');
    }
    if (status >= HttpStatus.internalServerError) {
      throw AiException(AiErrorCode.serverError, detail: 'HTTP $status');
    }

    final body = await _readLimitedBody(response, timeout);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw AiException(AiErrorCode.badResponse, detail: 'non-JSON model list');
    }
    return parseAiModelList(decoded);
  } catch (error) {
    throw _mapTransportError(error);
  } finally {
    client.close(force: true);
  }
}

/// 解析 OpenAI/Anthropic 风格的 `data[].id` 与目录风格的 `models[].slug`。
///
/// `models` 允许是任意形状；只有 `data` 缺失时才尝试解析它，避免供应商在
/// 标准 `data` 旁附带无关 `models` 字段时覆盖正确结果。
List<AiModelInfo> parseAiModelList(Object? decoded) {
  if (decoded is! Map) {
    throw AiException(
      AiErrorCode.badResponse,
      detail: 'model list is not object',
    );
  }
  final root = Map<String, Object?>.from(decoded);
  final data = root['data'];
  final Iterable<AiModelInfo> candidates;
  if (data is List) {
    candidates = data
        .whereType<Map>()
        .map((raw) => Map<String, Object?>.from(raw))
        .map(_modelFromData)
        .whereType<AiModelInfo>();
  } else if (data == null) {
    final models = root['models'];
    if (models is! List) {
      throw AiException(
        AiErrorCode.badResponse,
        detail: 'model list missing data/models',
      );
    }
    candidates = models
        .whereType<Map>()
        .map((raw) => Map<String, Object?>.from(raw))
        .map(_modelFromCatalog)
        .whereType<AiModelInfo>();
  } else {
    throw AiException(AiErrorCode.badResponse, detail: 'invalid model data');
  }

  final unique = <String, AiModelInfo>{};
  for (final model in candidates) {
    final id = model.id.trim();
    if (id.isEmpty) {
      continue;
    }
    final normalized = AiModelInfo(
      id: id,
      ownedBy: _normalizeOptional(model.ownedBy),
    );
    unique.putIfAbsent(id.toLowerCase(), () => normalized);
    if (unique.length > _maxModelCount) {
      throw AiException(
        AiErrorCode.badResponse,
        detail: 'too many models in model list',
      );
    }
  }
  final models = unique.values.toList(growable: false)
    ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
  return models;
}

AiModelInfo? _modelFromData(Map<String, Object?> raw) {
  final id = raw['id'];
  if (id is! String || id.trim().isEmpty) {
    return null;
  }
  final normalizedId = id.trim();
  return AiModelInfo(
    id: normalizedId,
    ownedBy: _string(raw['owned_by']) ?? _vendorFromModelId(normalizedId),
  );
}

AiModelInfo? _modelFromCatalog(Map<String, Object?> raw) {
  final id = _string(raw['slug']) ?? _string(raw['id']);
  if (id == null) {
    return null;
  }
  return AiModelInfo(
    id: id,
    ownedBy: _string(raw['owned_by']) ?? _vendorFromModelId(id),
  );
}

String? _vendorFromModelId(String id) {
  final slash = id.indexOf('/');
  if (slash <= 0) {
    return null;
  }
  final vendor = id.substring(0, slash).trim();
  return vendor.isEmpty ? null : vendor;
}

String? _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

String? _normalizeOptional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

bool _isRedirect(int status) =>
    status == HttpStatus.movedPermanently ||
    status == HttpStatus.found ||
    status == HttpStatus.seeOther ||
    status == HttpStatus.temporaryRedirect ||
    status == HttpStatus.permanentRedirect;

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

Future<String> _readLimitedBody(
  HttpClientResponse response,
  Duration timeout,
) async {
  final bytes = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in response.timeout(timeout)) {
    total += chunk.length;
    if (total > _maxModelResponseBytes) {
      throw AiException(
        AiErrorCode.badResponse,
        detail: 'model list response too large',
      );
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

AiException _mapTransportError(Object error) {
  if (error is AiException) {
    return error;
  }
  if (error is TimeoutException) {
    return AiException(AiErrorCode.timeout);
  }
  if (error is HandshakeException) {
    return AiException(AiErrorCode.tls);
  }
  if (error is SocketException) {
    return AiException(AiErrorCode.network, detail: error.message);
  }
  if (error is HttpException) {
    return AiException(AiErrorCode.network, detail: error.message);
  }
  if (error is FormatException) {
    return AiException(AiErrorCode.badResponse);
  }
  if (error is ArgumentError) {
    return AiException(AiErrorCode.badUrl);
  }
  return AiException(AiErrorCode.unknown, detail: '$error');
}
