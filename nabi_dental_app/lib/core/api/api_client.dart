import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../auth/token_storage.dart';
import '../errors/app_exception.dart';
import '../logging/app_logger.dart';
import '../security/device_id.dart';
import 'api_error.dart';

class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    required DeviceIdentity deviceIdentity,
    Dio? dio,
  })  : _tokenStorage = tokenStorage,
        _deviceIdentity = deviceIdentity,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.apiBaseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                headers: {'Content-Type': 'application/json'},
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.data is FormData) {
            options.headers.remove(Headers.contentTypeHeader);
          }
          final skipAuth = options.extra['skipAuth'] == true;
          if (!skipAuth) {
            final token = await _tokenStorage.readAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          final alreadyRetried = request.extra['retried'] == true;
          final path = request.path;
          final skipRefresh = request.extra['skipRefresh'] == true ||
              path.contains('/auth/change-password') ||
              path.contains('/auth/login');
          if (error.response?.statusCode == 401 &&
              request.extra['skipAuth'] != true &&
              !skipRefresh &&
              !alreadyRetried) {
            try {
              await _refresh();
              request.extra['retried'] = true;
              final token = await _tokenStorage.readAccessToken();
              if (token != null) {
                request.headers['Authorization'] = 'Bearer $token';
              }
              final response = await _dio.fetch(request);
              handler.resolve(response);
              return;
            } catch (_) {
              await _tokenStorage.clear();
              onSessionInvalid?.call();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final DeviceIdentity _deviceIdentity;
  void Function()? onSessionInvalid;

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    bool skipAuth = false,
    bool skipRefresh = false,
    ResponseType? responseType,
  }) {
    return _wrap(
      () => _dio.post<T>(
        path,
        data: data,
        options: Options(
          extra: {'skipAuth': skipAuth, 'skipRefresh': skipRefresh},
          responseType: responseType,
        ),
      ),
    );
  }

  Future<Response<T>> postMultipart<T>(String path, {required FormData data}) {
    return _wrap(
      () => _dio.post<T>(
        path,
        data: data,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      ),
    );
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query}) {
    return _wrap(() => _dio.get<T>(path, queryParameters: _query(query)));
  }

  Future<Response<T>> put<T>(String path, {Object? data}) {
    return _wrap(() => _dio.put<T>(path, data: data));
  }

  Future<Response<T>> patch<T>(String path, {Object? data}) {
    return _wrap(() => _dio.patch<T>(path, data: data));
  }

  Future<Response<T>> delete<T>(String path, {Map<String, dynamic>? query}) {
    return _wrap(() => _dio.delete<T>(path, queryParameters: _query(query)));
  }

  Future<Response<List<int>>> getBytes(String path, {Map<String, dynamic>? query}) {
    return _wrap(
      () => _dio.get<List<int>>(
        path,
        queryParameters: _query(query),
        options: Options(responseType: ResponseType.bytes),
      ),
    );
  }

  Map<String, dynamic>? _query(Map<String, dynamic>? query) {
    if (query == null) {
      return null;
    }
    return {
      for (final entry in query.entries) entry.key: entry.value is List ? entry.value : entry.value?.toString(),
    };
  }

  Future<void> _refresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      throw const UnauthorizedException();
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/refresh',
      data: {
        'refresh_token': refreshToken,
        'device_id': await _deviceIdentity.id(),
      },
      options: Options(extra: {'skipAuth': true}),
    );
    final body = response.data ?? {};
    await _tokenStorage.save(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
    );
  }

  Future<Response<T>> _wrap<T>(Future<Response<T>> Function() send) async {
    try {
      return await send();
    } on DioException catch (error) {
      final path = error.requestOptions.path;
      final status = error.response?.statusCode;
      AppLogger.error('api', error.type.name, path: path, status: status);
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw const OfflineException();
      }
      throw parseApiError(error.response?.data, status);
    }
  }
}
