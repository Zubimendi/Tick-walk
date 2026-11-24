import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../data/api/auth.dart';
import '../../ui/tokens.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final authService = ref.watch(authServiceProvider);
    final isSignedIn = authService.isSignedIn;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        title: Text(
          'Cloud Backup & Account',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: tokens.text,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(tokens.screenPadding),
        children: [
          if (isSignedIn) ...[
            // Signed-in profile card
            Card(
              elevation: 0,
              color: tokens.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusCard),
                side: BorderSide(color: tokens.border),
              ),
              child: Padding(
                padding: EdgeInsets.all(tokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: tokens.pass.withValues(alpha: 0.15),
                          child: Icon(Icons.cloud_done, color: tokens.pass),
                        ),
                        SizedBox(width: tokens.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                authService.currentEmail ?? 'Signed In',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: tokens.text,
                                ),
                              ),
                              Text(
                                'User ID: ${authService.currentUserId}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: tokens.space16),
                    Container(
                      padding: EdgeInsets.all(tokens.space12),
                      decoration: BoxDecoration(
                        color: tokens.pass.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(tokens.radiusCard),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: tokens.pass, size: 20),
                          SizedBox(width: tokens.space8),
                          Expanded(
                            child: Text(
                              'Cloud sync active. Your checklists and photos upload automatically.',
                              style: theme.textTheme.bodySmall?.copyWith(color: tokens.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: tokens.space16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await authService.signOut();
                        setState(() {});
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tokens.fail,
                        side: BorderSide(color: tokens.fail),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Sign in form
            Card(
              elevation: 0,
              color: tokens.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusCard),
                side: BorderSide(color: tokens.border),
              ),
              child: Padding(
                padding: EdgeInsets.all(tokens.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: tokens.primary.withValues(alpha: 0.12),
                          child: Icon(Icons.cloud_outlined, color: tokens.primary),
                        ),
                        SizedBox(width: tokens.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Optional Cloud Backup',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: tokens.text,
                                ),
                              ),
                              Text(
                                'Sign in to back up and sync your site evidence.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: tokens.space16),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: EdgeInsets.all(tokens.space8),
                        decoration: BoxDecoration(
                          color: tokens.fail.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(tokens.radiusCard),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: tokens.fail, fontSize: 13),
                        ),
                      ),
                      SizedBox(height: tokens.space12),
                    ],

                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(tokens.radiusCard),
                        ),
                      ),
                    ),
                    SizedBox(height: tokens.space12),

                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(tokens.radiusCard),
                        ),
                      ),
                    ),
                    SizedBox(height: tokens.space16),

                    FilledButton(
                      key: const ValueKey('sign_in_button'),
                      onPressed: _isLoading ? null : _handleSignIn,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Sign In to Sync'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);
    final res = await authService.signIn(email: email, password: password);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (res.isErr) {
      setState(() => _errorMessage = res.errorOrNull!.message);
      return;
    }

    final authResult = res.valueOrNull!;
    switch (authResult) {
      case AuthSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully.')),
        );
        setState(() {});

      case DifferentAccountDetected(
          :final previousOwnerId,
          :final newOwnerId,
          :final newEmail,
        ):
        // Show Account Guard prompt: "Replace local data or cancel" (Rule 7 & T18)
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Different Account Detected'),
            content: Text(
              'This device is currently linked to account ($previousOwnerId).\n\n'
              'Signing in as ($newEmail) will replace local inspection data on this device with the new account\'s data.\n\n'
              'Do you want to replace local data or cancel?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Replace Local Data'),
              ),
            ],
          ),
        );

        if (!mounted) return;

        if (confirmed == true) {
          final switchRes = await authService.confirmAccountSwitch(newOwnerId);
          if (switchRes.isOk && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Switched account and reset local sync data.')),
            );
            setState(() {});
          }
        } else {
          await authService.cancelAccountSwitch();
          setState(() {});
        }
    }
  }
}
