import 'models.dart';

sealed class CompletionBlocker {
  const CompletionBlocker({
    required this.itemId,
    required this.prompt,
    required this.sectionTitle,
  });

  final String itemId;
  final String prompt;
  final String sectionTitle;

  String get description;
}

class UnansweredRequiredBlocker extends CompletionBlocker {
  const UnansweredRequiredBlocker({
    required super.itemId,
    required super.prompt,
    required super.sectionTitle,
  });

  @override
  String get description => 'Unanswered: $prompt';
}

class MissingPhotoBlocker extends CompletionBlocker {
  const MissingPhotoBlocker({
    required super.itemId,
    required super.prompt,
    required super.sectionTitle,
  });

  @override
  String get description => 'Photo required for failed item: $prompt';
}

/// Pure domain validation function.
/// Invariant: No Flutter, Drift, or platform imports.
/// Blockers:
/// 1. Any required item that is not answered
/// 2. Any pass_fail item with response 'fail' and photoRequiredOnFail == true
///    that has 0 non-deleted photos.
List<CompletionBlocker> validateCompletion({
  required List<InspectionItem> items,
  required Map<String, int> photoCountByItem,
}) {
  final blockers = <CompletionBlocker>[];

  for (final item in items) {
    // 1. Required item answered check
    if (item.required && !item.isAnswered) {
      blockers.add(
        UnansweredRequiredBlocker(
          itemId: item.id,
          prompt: item.prompt,
          sectionTitle: item.sectionTitle,
        ),
      );
    }

    // 2. Photo required on fail check
    if (item.itemType == ItemType.passFail &&
        item.response == ItemResponse.fail &&
        item.photoRequiredOnFail) {
      final photos = photoCountByItem[item.id] ?? 0;
      if (photos == 0) {
        blockers.add(
          MissingPhotoBlocker(
            itemId: item.id,
            prompt: item.prompt,
            sectionTitle: item.sectionTitle,
          ),
        );
      }
    }
  }

  return List.unmodifiable(blockers);
}
