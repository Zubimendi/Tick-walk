import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../ui/tokens.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  var _addStarters = true;
  var _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSubmitting = true);

    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.setInspectorName(name);
    await settingsRepo.setOnboardingDone();

    if (mounted) {
      context.go('/inspections');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(tokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 40,
                      color: tokens.primary,
                    ),
                  ),
                  SizedBox(height: tokens.space24),
                  Text(
                    'Tickwalk',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: tokens.space8),
                  Text(
                    'Site inspection checklists with photo and GPS evidence that work with no signal.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: tokens.space32),
                  Text(
                    'Inspector Name',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.text,
                    ),
                  ),
                  SizedBox(height: tokens.space8),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'e.g. Francis Offiong',
                      filled: true,
                      fillColor: tokens.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusCard),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusCard),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusCard),
                        borderSide: BorderSide(color: tokens.primary, width: 2),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  SizedBox(height: tokens.space16),
                  SwitchListTile(
                    title: Text(
                      'Include starter templates',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tokens.text,
                      ),
                    ),
                    subtitle: Text(
                      'Site safety, Rental move-in, Generator room',
                      style: theme.textTheme.bodySmall,
                    ),
                    value: _addStarters,
                    activeThumbColor: tokens.primary,
                    onChanged: (val) => setState(() => _addStarters = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SizedBox(height: tokens.space32),
                  FilledButton(
                    onPressed: _nameController.text.trim().isNotEmpty && !_isSubmitting
                        ? _submit
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: Size.fromHeight(tokens.answerButtonHeight),
                      backgroundColor: tokens.primary,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Get Started'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
