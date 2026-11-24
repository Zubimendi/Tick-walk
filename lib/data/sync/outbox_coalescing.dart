import 'dart:convert';
import 'package:tickwalk/domain/models.dart';

/// Pure domain outbox coalescing logic.
/// Invariant: Pure domain logic with no Flutter, Drift, or platform imports.
/// Coalescing rules (Section 8.3):
/// - create then updates -> One create with final state
/// - updates then updates -> One update with latest values
/// - create then delete (never synced) -> Both dropped (and any queued upload cancelled)
/// - updates then delete -> One delete
/// Rapid answer changes on the same item collapse to one update.

/// Merges two JSON object payloads, where keys in [nextJson] override [prevJson].
String mergePayloads(String prevJson, String nextJson) {
  try {
    final prev = jsonDecode(prevJson);
    final next = jsonDecode(nextJson);

    if (prev is Map<String, dynamic> && next is Map<String, dynamic>) {
      final merged = <String, dynamic>{...prev, ...next};
      return jsonEncode(merged);
    }
  } catch (_) {
    // If decoding fails, next payload takes precedence
  }
  return nextJson;
}

/// Coalesces an ordered list of [OutboxEntry] according to Section 8.3 rules.
/// Returns a compacted list maintaining strict causal order.
List<OutboxEntry> coalesceOutbox(List<OutboxEntry> entries) {
  if (entries.isEmpty) return const [];

  // Key: "$entity:$entityId"
  final entityKeyToIndices = <String, List<int>>{};
  final result = <OutboxEntry>[];

  // We track media entries separately so that if an attachment's create is cancelled,
  // the media entry is also dropped.
  final mediaIndicesByAttachmentId = <String, int>{};

  for (final entry in entries) {
    if (entry.lane == OutboxLane.media) {
      final idx = result.length;
      result.add(entry);
      if (entry.entity == OutboxEntity.attachment && entry.op == OutboxOp.create) {
        mediaIndicesByAttachmentId[entry.entityId] = idx;
      }
      continue;
    }

    final key = '${entry.entity.value}:${entry.entityId}';
    final existingIndices = entityKeyToIndices[key];

    if (existingIndices == null || existingIndices.isEmpty) {
      // First op for this entity
      final idx = result.length;
      result.add(entry);
      entityKeyToIndices[key] = [idx];
      continue;
    }

    // Previous active entry index for this entity
    final prevIdx = existingIndices.last;
    final prevEntry = result[prevIdx];

    if (prevEntry.op == OutboxOp.create && entry.op == OutboxOp.update) {
      // create then update -> One create with merged payload
      final mergedPayload = mergePayloads(prevEntry.payload, entry.payload);
      result[prevIdx] = prevEntry.copyWith(
        payload: mergedPayload,
      );
    } else if (prevEntry.op == OutboxOp.update && entry.op == OutboxOp.update) {
      // update then update -> One update with latest values
      final mergedPayload = mergePayloads(prevEntry.payload, entry.payload);
      result[prevIdx] = prevEntry.copyWith(
        payload: mergedPayload,
      );
    } else if (prevEntry.op == OutboxOp.create && entry.op == OutboxOp.delete) {
      // create then delete (never synced) -> Both dropped
      // Mark previous create as dropped (placeholder null to maintain index stability)
      result[prevIdx] = _emptyDroppedEntry;
      existingIndices.removeLast();

      // If it's an attachment, also drop any queued media upload
      if (entry.entity == OutboxEntity.attachment) {
        final mediaIdx = mediaIndicesByAttachmentId[entry.entityId];
        if (mediaIdx != null && mediaIdx < result.length) {
          result[mediaIdx] = _emptyDroppedEntry;
          mediaIndicesByAttachmentId.remove(entry.entityId);
        }
      }
    } else if (prevEntry.op == OutboxOp.update && entry.op == OutboxOp.delete) {
      // update then delete -> One delete
      result[prevIdx] = prevEntry.copyWith(
        op: OutboxOp.delete,
        payload: entry.payload,
      );
    } else {
      // Any other combination (e.g. create after delete): append
      final idx = result.length;
      result.add(entry);
      existingIndices.add(idx);
    }
  }

  // Filter out any dropped entries
  return result.where((e) => e.seq != -999).toList();
}

/// Sentinel entry representing a dropped outbox mutation.
const _emptyDroppedEntry = OutboxEntry(
  seq: -999,
  entity: OutboxEntity.template,
  entityId: '',
  op: OutboxOp.delete,
  payload: '',
  lane: OutboxLane.records,
  createdAt: 0,
);
