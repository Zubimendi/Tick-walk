import 'package:flutter/material.dart';
import '../../ui/tokens.dart';

class UploadsScreen extends StatelessWidget {
  const UploadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Queue'),
      ),
      body: Center(
        child: Text(
          'Queue is empty',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
      ),
    );
  }
}
