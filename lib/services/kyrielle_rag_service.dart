import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'gemini_client.dart';
import 'kyrielle_knowledge_base.dart';
import 'kyrielle_safety_manual.dart';

/// The full RAG corpus — app-specific FAQ facts plus the DENR Hiking Safety
/// Manual chunks. Still small enough (~53 entries) for brute-force
/// similarity search on-device.
final List<KyrielleKnowledgeChunk> _kyrielleCorpus = [
  ...kyrielleKnowledgeBase,
  ...kyrielleSafetyManualChunks,
];

/// Lightweight RAG (Retrieval-Augmented Generation) for Kyrielle's
/// knowledge base. Retrieval is brute-force cosine similarity over a
/// modest number of precomputed embeddings (~53 entries) rather than a
/// hosted vector database — at this corpus size a vector DB adds real
/// infrastructure for no practical benefit over just comparing the
/// vectors directly on-device.
class KyrielleRagService {
  KyrielleRagService._();
  static final KyrielleRagService instance = KyrielleRagService._();

  Map<String, List<double>>? _cachedEmbeddings;
  Future<void>? _buildFuture;

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/kyrielle_knowledge_embeddings.json');
  }

  // The knowledge base rarely changes, so its embeddings are computed once
  // and cached on-device (bump kyrielleKnowledgeBaseVersion to invalidate) —
  // only the incoming question needs a fresh embedding per call.
  Future<Map<String, List<double>>> _loadOrBuildEmbeddings(
    String apiKey,
  ) async {
    if (_cachedEmbeddings != null) {
      return _cachedEmbeddings!;
    }
    // Multiple near-simultaneous questions before the first build finishes
    // should all wait on that same build rather than each kicking off their
    // own round of embedding calls.
    if (_buildFuture != null) {
      await _buildFuture;
      return _cachedEmbeddings ?? {};
    }

    final completer = Completer<void>();
    _buildFuture = completer.future;
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        try {
          final decoded = json.decode(await file.readAsString());
          if (decoded is Map<String, dynamic> &&
              decoded['version'] == kyrielleKnowledgeBaseVersion) {
            final entries = decoded['embeddings'] as Map<String, dynamic>;
            _cachedEmbeddings = entries.map(
              (key, value) => MapEntry(
                key,
                (value as List).map((v) => (v as num).toDouble()).toList(),
              ),
            );
            return _cachedEmbeddings!;
          }
        } catch (_) {
          // Corrupt/unreadable cache — fall through and rebuild.
        }
      }

      // Embedded in small concurrent batches rather than one-by-one — with
      // ~53 chunks, a strictly sequential first build would take a while.
      final embeddings = <String, List<double>>{};
      const batchSize = 8;
      for (var start = 0; start < _kyrielleCorpus.length; start += batchSize) {
        final batch = _kyrielleCorpus.skip(start).take(batchSize);
        final results = await Future.wait(
          batch.map(
            (chunk) async => MapEntry(
              chunk.id,
              await fetchGeminiEmbedding(apiKey: apiKey, text: chunk.text),
            ),
          ),
        );
        for (final result in results) {
          if (result.value != null) {
            embeddings[result.key] = result.value!;
          }
        }
      }
      _cachedEmbeddings = embeddings;

      if (embeddings.isNotEmpty) {
        try {
          await file.writeAsString(
            json.encode({
              'version': kyrielleKnowledgeBaseVersion,
              'embeddings': embeddings,
            }),
          );
        } catch (_) {
          // Caching is an optimization — fine to skip if the write fails.
        }
      }
      return embeddings;
    } finally {
      completer.complete();
      _buildFuture = null;
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Returns the [topK] most relevant knowledge-base chunks for [question],
  /// ranked by embedding similarity. Returns an empty list (fail-open) if
  /// the API key is missing, embeddings are unavailable (e.g. depleted
  /// Gemini credits), or nothing clears [minScore] — callers must treat an
  /// empty result as "answer without retrieved context", never an error.
  ///
  /// [minScore] is a starting default, not a tuned value — adjust it once
  /// there's a working API key to test real questions against.
  Future<List<String>> retrieveRelevantAnswers(
    String question, {
    required String apiKey,
    int topK = 3,
    double minScore = 0.5,
  }) async {
    if (apiKey.isEmpty || question.trim().isEmpty) {
      debugPrint('[KyrielleRAG] skipped — no API key or empty question');
      return const [];
    }

    final corpusEmbeddings = await _loadOrBuildEmbeddings(apiKey);
    debugPrint(
      '[KyrielleRAG] corpus ready: ${corpusEmbeddings.length}/${_kyrielleCorpus.length} chunks embedded',
    );
    if (corpusEmbeddings.isEmpty) {
      return const [];
    }

    final questionVector = await fetchGeminiEmbedding(
      apiKey: apiKey,
      text: question,
    );
    if (questionVector == null) {
      debugPrint('[KyrielleRAG] could not embed the question — Gemini call failed');
      return const [];
    }

    final scored = <MapEntry<String, double>>[
      for (final entry in corpusEmbeddings.entries)
        MapEntry(entry.key, _cosineSimilarity(questionVector, entry.value)),
    ]..sort((a, b) => b.value.compareTo(a.value));

    debugPrint(
      '[KyrielleRAG] top matches for "$question": '
      '${scored.take(5).map((e) => '${e.key}=${e.value.toStringAsFixed(3)}').join(', ')}',
    );

    final textById = {
      for (final chunk in _kyrielleCorpus) chunk.id: chunk.text,
    };
    final results = scored
        .where((entry) => entry.value >= minScore)
        .take(topK)
        .map((entry) => textById[entry.key])
        .whereType<String>()
        .toList();
    debugPrint('[KyrielleRAG] retrieved ${results.length} chunk(s) above minScore=$minScore');
    return results;
  }
}
