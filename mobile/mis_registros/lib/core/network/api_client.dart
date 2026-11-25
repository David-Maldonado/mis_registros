import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    String? baseUrl,
    String? Function()? accessTokenProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/$'), ''),
        _accessTokenProvider = accessTokenProvider ?? _defaultTokenProvider;

  final http.Client _httpClient;
  final String _baseUrl;
  final String? Function() _accessTokenProvider;

  static String? _defaultTokenProvider() {
    return Supabase.instance.client.auth.currentSession?.accessToken;
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final uri = _buildUri(path, query);
    final response = await _httpClient.get(uri, headers: _headers());
    return _handleResponse(response);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final uri = _buildUri(path);
    final response = await _httpClient.post(
      uri,
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final uri = _buildUri(path);
    final response = await _httpClient.put(
      uri,
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final uri = _buildUri(path);
    final response = await _httpClient.patch(
      uri,
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<dynamic> delete(String path) async {
    final uri = _buildUri(path);
    final response = await _httpClient.delete(uri, headers: _headers());
    return _handleResponse(response);
  }

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$_baseUrl$normalizedPath');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: query);
  }

  Map<String, String> _headers() {
    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const ApiException('Sesión no autenticada.', statusCode: 401);
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  dynamic _handleResponse(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      final rawMessage = decoded['message'];
      if (rawMessage is List && rawMessage.isNotEmpty) {
        throw ApiException(rawMessage.join('\n'), statusCode: response.statusCode);
      }
      if (rawMessage is String && rawMessage.isNotEmpty) {
        throw ApiException(rawMessage, statusCode: response.statusCode);
      }
    }

    throw ApiException(
      'Error en la solicitud (${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }
}
