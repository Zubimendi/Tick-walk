import 'package:flutter/material.dart';
import '../../ui/tokens.dart';

class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
      ),
      body: Center(
        child: Text(
          'Checklist Templates',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
      ),
    );
  }
}
