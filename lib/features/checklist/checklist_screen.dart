import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../domain/models.dart';
import '../../ui/tokens.dart';

class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({
    super.key,
    required this.inspectionId,
  });

  final String inspectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final AsyncValue<Inspection?> inspectionAsync =
        ref.watch(singleInspectionProvider(inspectionId));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        title: inspectionAsync.when(
          data: (Inspection? insp) =>
              Text(insp?.siteName ?? 'Inspection Checklist'),
          loading: () => const Text('Loading...'),
          error: (Object _, StackTrace _) =>
              const Text('Inspection Checklist'),
        ),
      ),
      body: Center(
        child: Text(
          'Checklist for $inspectionId',
          style: TextStyle(color: tokens.text),
        ),
      ),
    );
  }
}
