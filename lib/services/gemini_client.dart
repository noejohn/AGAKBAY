import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Shared Gemini call plumbing, extracted from the original
/// `_HikeAssistantScreenState` implementation so both the hike-assistant
/// chat and `AgakController` (for optional recommendation phrasing) use the
/// exact same request shape instead of duplicating it.
const MethodChannel agakConfigChannel = MethodChannel('com.example.tunga/config');

/// Reads the Gemini API key via the same platform-config channel the app
/// already uses for the Maps/Weather keys. Returns '' if unavailable.
Future<String> loadGeminiApiKey() async {
  try {
    final apiKey = await agakConfigChannel.invokeMethod<String>('getAiApiKey');
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      return apiKey.trim();
    }
  } catch (_) {
    // Ignore missing AI config.
  }
  return '';
}

/// Calls the Gemini `generateContent` endpoint. Returns '' on any failure
/// (missing key, network error, non-200, unexpected shape) — callers must
/// treat an empty string as "fall back to a non-AI answer", never as an
/// error to surface to the user.
Future<String> fetchGeminiResponse({
  required String apiKey,
  required String systemInstruction,
  required String prompt,
  double temperature = 0.7,
  int maxOutputTokens = 260,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (apiKey.isEmpty) {
    return '';
  }

  try {
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/gemini-flash-lite-latest:generateContent',
      {'key': apiKey},
    );
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'systemInstruction': {
              'parts': [
                {'text': systemInstruction},
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {
              'temperature': temperature,
              'maxOutputTokens': maxOutputTokens,
            },
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      debugPrint(
        'Gemini request failed: ${response.statusCode} ${response.body}',
      );
      return '';
    }

    final body = json.decode(response.body);
    final candidates = body['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final content = candidates.first['content'];
      if (content is Map<String, dynamic>) {
        final parts = content['parts'];
        if (parts is List && parts.isNotEmpty) {
          return parts.first['text']?.toString().trim() ?? '';
        }
      }
    }
  } catch (error) {
    debugPrint('Gemini request threw: $error');
  }

  return '';
}
