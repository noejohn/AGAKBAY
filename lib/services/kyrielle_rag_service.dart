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

const Set<String> _queryStopWords = {
  'a',
  'about',
  'an',
  'and',
  'are',
  'can',
  'do',
  'does',
  'for',
  'how',
  'i',
  'in',
  'is',
  'it',
  'me',
  'my',
  'of',
  'on',
  'please',
  'the',
  'to',
  'what',
  'when',
  'where',
  'which',
  'with',
  'you',
};

List<KyrielleKnowledgeChunk> retrieveRelevantChunksLocally(
  String question, {
  int topK = 3,
}) {
  final normalizedQuestion = question
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  final queryTokens = RegExp(r'[a-z0-9]+')
      .allMatches(normalizedQuestion)
      .map((match) => match.group(0)!)
      .where((token) => !_queryStopWords.contains(token))
      .toSet();
  if (queryTokens.isEmpty || topK <= 0) {
    return const [];
  }

  final scored = <({KyrielleKnowledgeChunk chunk, double score})>[];
  for (final chunk in _kyrielleCorpus) {
    final normalizedText = chunk.text.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      ' ',
    );
    final textTokens = RegExp(
      r'[a-z0-9]+',
    ).allMatches(normalizedText).map((match) => match.group(0)!).toSet();
    final overlap = queryTokens.intersection(textTokens).length;
    if (overlap == 0) {
      continue;
    }
    final phraseMatch =
        normalizedQuestion.length >= 12 &&
        normalizedText.contains(normalizedQuestion);
    scored.add((
      chunk: chunk,
      score: overlap / queryTokens.length + (phraseMatch ? 1 : 0),
    ));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(topK).map((entry) => entry.chunk).toList();
}

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
    Iterable<KyrielleKnowledgeChunk> chunks,
  ) async {
    final requestedChunks = chunks.toList(growable: false);
    if (_cachedEmbeddings != null &&
        requestedChunks.every(
          (chunk) => _isValidEmbedding(_cachedEmbeddings![chunk.id]),
        )) {
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
      final embeddings = _cachedEmbeddings ?? <String, List<double>>{};
      final file = await _cacheFile();
      if (embeddings.isEmpty && await file.exists()) {
        try {
          final decoded = json.decode(await file.readAsString());
          if (decoded is Map<String, dynamic> &&
              decoded['version'] == kyrielleKnowledgeBaseVersion) {
            final entries = decoded['embeddings'] as Map<String, dynamic>;
            final knownChunkIds = _kyrielleCorpus
                .map((chunk) => chunk.id)
                .toSet();
            for (final entry in entries.entries) {
              if (!knownChunkIds.contains(entry.key) || entry.value is! List) {
                continue;
              }
              final vector = (entry.value as List)
                  .whereType<num>()
                  .map((value) => value.toDouble())
                  .toList(growable: false);
              if (_isValidEmbedding(vector)) {
                embeddings[entry.key] = vector;
              }
            }
          }
        } catch (_) {
          // Corrupt/unreadable cache — fall through and rebuild.
        }
      }

      _cachedEmbeddings = embeddings;
      final missingChunks = requestedChunks
          .where((chunk) => !_isValidEmbedding(embeddings[chunk.id]))
          .toList(growable: false);
      const batchSize = 8;
      for (var start = 0; start < missingChunks.length; start += batchSize) {
        final batch = missingChunks.skip(start).take(batchSize);
        final results = await Future.wait(
          batch.map(
            (chunk) async => MapEntry(
              chunk.id,
              await fetchGeminiEmbedding(apiKey: apiKey, text: chunk.text),
            ),
          ),
        );
        for (final result in results) {
          if (_isValidEmbedding(result.value)) {
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

  bool _isValidEmbedding(List<double>? embedding) {
    return embedding != null &&
        embedding.isNotEmpty &&
        embedding.every((value) => value.isFinite);
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Uses local keyword matching first, then reranks matching chunks with
  /// Gemini embeddings when available. Retrieval remains useful offline or
  /// when Gemini embeddings fail.
  Future<List<String>> retrieveRelevantAnswers(
    String question, {
    required String apiKey,
    int topK = 3,
    double minScore = 0.5,
  }) async {
    if (question.trim().isEmpty || topK <= 0) {
      return const [];
    }

    final localMatches = retrieveRelevantChunksLocally(
      question,
      topK: max(topK * 4, 12),
    );
    if (apiKey.isEmpty || localMatches.isEmpty) {
      return localMatches.take(topK).map((chunk) => chunk.text).toList();
    }

    try {
      final corpusEmbeddings = await _loadOrBuildEmbeddings(
        apiKey,
        localMatches,
      );
      final questionVector = await fetchGeminiEmbedding(
        apiKey: apiKey,
        text: question,
      );
      if (questionVector == null) {
        return localMatches.take(topK).map((chunk) => chunk.text).toList();
      }

      final localScores = <String, double>{};
      final localRanked = retrieveRelevantChunksLocally(
        question,
        topK: max(topK * 4, 12),
      );
      for (var index = 0; index < localRanked.length; index++) {
        localScores[localRanked[index].id] =
            1 - index / max(localRanked.length, 1);
      }

      final textById = {
        for (final chunk in _kyrielleCorpus) chunk.id: chunk.text,
      };
      final scored = <({String id, double score})>[];
      for (final chunk in localMatches) {
        final embedding = corpusEmbeddings[chunk.id];
        if (!_isValidEmbedding(embedding)) {
          continue;
        }
        final similarity = _cosineSimilarity(questionVector, embedding!);
        final lexicalScore = localScores[chunk.id] ?? 0;
        if (similarity >= minScore || lexicalScore > 0) {
          scored.add((id: chunk.id, score: similarity + lexicalScore * 0.35));
        }
      }
      scored.sort((a, b) => b.score.compareTo(a.score));

      final semanticResults = scored
          .take(topK)
          .map((entry) => textById[entry.id])
          .whereType<String>()
          .toList();
      if (semanticResults.isNotEmpty) {
        return semanticResults;
      }
    } catch (error) {
      debugPrint('[KyrielleRAG] semantic retrieval failed: $error');
    }

    return localMatches.take(topK).map((chunk) => chunk.text).toList();
  }
}
