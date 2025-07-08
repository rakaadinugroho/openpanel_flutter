import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:logger/logger.dart';
import 'package:openpanel_flutter/openpanel_flutter.dart';
import 'package:openpanel_flutter/src/constants/constants.dart';
import 'package:openpanel_flutter/src/models/post_event_payload.dart';
import 'package:openpanel_flutter/src/models/update_profile_payload.dart';

import 'device_user_agent.dart';

typedef ApiResponse<T, E> = ({T? response, E? error});

class OpenpanelHttpClient {
  late final Dio _dio;
  final bool verbose;
  final Logger _logger;

  OpenpanelHttpClient({
    required this.verbose,
    required Logger logger,
  }) : _logger = logger;

  Future<void> init(OpenpanelOptions options) async {
    _dio = Dio(
      BaseOptions(
        baseUrl: options.url ?? kDefaultBaseUrl,
        headers: {
          'openpanel-client-id': options.clientId,
          'openpanel-sdk-name': 'openpanel-flutter',
          'openpanel-sdk-version': '0.2.0',
          if (options.clientSecret != null) 'openpanel-client-secret': options.clientSecret,
          'User-Agent': await DeviceUserAgent().getUserAgent(),
        },
      ),
    );
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
    if (options.verbose) {
      _dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
    }
  }

  void updateProfile({
    required UpdateProfilePayload payload,
    required Map<String, dynamic> stateProperties,
  }) {
    runApiCall(() async {
      await _dio.post('/profile', data: {
        ...payload.toJson(),
        'properties': {
          ...payload.properties,
          ...stateProperties,
        }
      });
    });
  }

  void increment({
    required String profileId,
    required String property,
    required int value,
  }) {
    runApiCall(() async {
      _dio.post('/profile/increment', data: {
        'profileId': profileId,
        'property': property,
        'value': value,
      });
    });
  }

  void decrement({
    required String profileId,
    required String property,
    required int value,
  }) {
    runApiCall(() async {
      _dio.post('/profile/decrement', data: {
        'profileId': profileId,
        'property': property,
        'value': value,
      });
    });
  }

  Future<String?> event({required PostEventPayload payload}) async {
    if (verbose) {
      _logger.i('OPENPANEL > Sending HTTP request to /event: ${payload.toJson()}');
    }
    
    final response = await runApiCall(() async {
      try {
        final response = await _dio.post('/event', data: payload.toJson());
        if (verbose) {
          _logger.i('OPENPANEL > Received response: ${response.data}');
        }
        return response.data as String;
      } catch (e, stackTrace) {
        if (verbose) {
          _logger.e('OPENPANEL > Error sending event', error: e, stackTrace: stackTrace);
        }
        rethrow;
      }
    });

    if (response.error != null) {
      if (verbose) {
        _logger.e('OPENPANEL > Error in event API call', error: response.error);
      }
      return null;
    }

    return response.response;
  }

  Future<ApiResponse> runApiCall<T, E>(Future<T> Function() apiCall) async {
    try {
      final response = await apiCall();

      return (response: response, error: null);
    } on DioException catch (e) {
      _logger.e(e.message);
      return (response: null, error: e);
    } on SocketException catch (e) {
      _logError('Failed to connect to the internet.');
      return (response: null, error: e);
    }
  }

  void _logError(String message) {
    if (verbose) {
      _logger.e(message);
    }
  }
}
