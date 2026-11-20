import 'package:flutter/material.dart';
import '../../ui/tokens.dart';

class InspectionsScreen extends StatelessWidget {
  const InspectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspections'),
      ),
      body: Center(
        child: Text(
          'No inspections yet',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
      ),
    );
  }
}
