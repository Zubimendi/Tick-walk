import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../app_providers.dart';
import '../../ui/tokens.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final settingsAsync = ref.watch(settingsMapProvider);
    final settings = settingsAsync.value ?? {};

    final inspectorName = settings['inspector_name'] ?? 'Not set';
    final qualityProfile = settings['quality_profile'] ?? 'standard';
    final wifiOnly = settings['wifi_only'] != 'false';
    final syncOwner = settings['sync_owner_id'];
    final authService = ref.watch(authServiceProvider);
    final isSignedIn = authService.isSignedIn;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: EdgeInsets.all(tokens.screenPadding),
        children: [
          // Cloud Account & Backup tile
          Card(
            elevation: 0,
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusCard),
              side: BorderSide(color: tokens.border),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isSignedIn
                    ? tokens.pass.withValues(alpha: 0.15)
                    : tokens.primary.withValues(alpha: 0.15),
                child: Icon(
                  isSignedIn ? Icons.cloud_done : Icons.cloud_outlined,
                  color: isSignedIn ? tokens.pass : tokens.primary,
                ),
              ),
              title: const Text(
                'Cloud Backup & Account',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                isSignedIn
                    ? (authService.currentEmail ?? 'Sync active')
                    : (syncOwner != null
                        ? 'Linked to account ($syncOwner) - Signed out'
                        : 'Optional cloud backup disabled'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/account'),
            ),
          ),
          SizedBox(height: tokens.space16),

          // Inspector Profile
          Text(
            'Inspector Profile',
            style: theme.textTheme.titleSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: tokens.space8),
          Card(
            elevation: 0,
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusCard),
              side: BorderSide(color: tokens.border),
            ),
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Inspector Name'),
              subtitle: Text(inspectorName),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () => _editInspectorName(context, ref, inspectorName),
            ),
          ),
          SizedBox(height: tokens.space16),

          // Capture & Upload Settings
          Text(
            'Capture & Storage',
            style: theme.textTheme.titleSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: tokens.space8),
          Card(
            elevation: 0,
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusCard),
              side: BorderSide(color: tokens.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_size_select_actual_outlined),
                  title: const Text('Photo Quality Profile'),
                  subtitle: Text(
                    switch (qualityProfile) {
                      'low' => 'Low data (1280px, 65 quality)',
                      'high' => 'High resolution (2048px, 85 quality)',
                      _ => 'Standard (1600px, 75 quality)',
                    },
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickQualityProfile(context, ref, qualityProfile),
                ),
                Divider(height: 1, color: tokens.border),
                SwitchListTile(
                  secondary: const Icon(Icons.wifi_outlined),
                  title: const Text('Upload over Wi-Fi only'),
                  subtitle: const Text('Save mobile data by pausing media sync until on Wi-Fi'),
                  value: wifiOnly,
                  onChanged: (val) {
                    ref.read(settingsRepositoryProvider).setWifiOnly(val);
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.space16),

          // Appearance
          Text(
            'Appearance',
            style: theme.textTheme.titleSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: tokens.space8),
          Card(
            elevation: 0,
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusCard),
              side: BorderSide(color: tokens.border),
            ),
            child: ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Theme Mode'),
              subtitle: Text(ref.watch(themeModeProvider).name.toUpperCase()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickThemeMode(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editInspectorName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current == 'Not set' ? '' : current);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Inspector Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Full Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await ref.read(settingsRepositoryProvider).setInspectorName(newName);
    }
  }

  Future<void> _pickQualityProfile(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Photo Quality Profile'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('low'),
            child: const Text('Low data (1280px, 65 quality)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('standard'),
            child: const Text('Standard (1600px, 75 quality)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('high'),
            child: const Text('High resolution (2048px, 85 quality)'),
          ),
        ],
      ),
    );

    if (selected != null) {
      await ref.read(settingsRepositoryProvider).set('quality_profile', selected);
    }
  }

  Future<void> _pickThemeMode(BuildContext context, WidgetRef ref) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme Mode'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(ThemeMode.system),
            child: const Text('System Default'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(ThemeMode.light),
            child: const Text('Light Theme'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(ThemeMode.dark),
            child: const Text('Dark Theme'),
          ),
        ],
      ),
    );

    if (selected != null) {
      ref.read(themeModeProvider.notifier).setThemeMode(selected);
    }
  }
}
