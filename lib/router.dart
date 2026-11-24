import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_providers.dart';
import 'features/account/account_screen.dart';
import 'features/checklist/checklist_screen.dart';
import 'features/checklist/photo_viewer_screen.dart';
import 'features/checklist/review_screen.dart';
import 'features/inspections/inspections_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/templates/templates_screen.dart';
import 'features/uploads/uploads_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final onboardingDone = ref.watch(onboardingDoneProvider);

  return GoRouter(
    initialLocation: onboardingDone ? '/inspections' : '/onboarding',
    redirect: (context, state) {
      final onOnboarding = state.uri.path == '/onboarding';
      if (!onboardingDone && !onOnboarding) {
        return '/onboarding';
      }
      if (onboardingDone && onOnboarding) {
        return '/inspections';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: '/inspections/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ChecklistScreen(inspectionId: id);
        },
        routes: [
          GoRoute(
            path: 'review',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ReviewScreen(inspectionId: id);
            },
          ),
          GoRoute(
            path: 'photos/:attachmentId',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final attachmentId = state.pathParameters['attachmentId']!;
              return PhotoViewerScreen(
                inspectionId: id,
                attachmentId: attachmentId,
              );
            },
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inspections',
                builder: (context, state) => const InspectionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/templates',
                builder: (context, state) => const TemplatesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/uploads',
                builder: (context, state) => const UploadsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _ScaffoldWithNavBar extends StatelessWidget {
  const _ScaffoldWithNavBar({
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Inspections',
          ),
          NavigationDestination(
            icon: Icon(Icons.format_list_bulleted_outlined),
            selectedIcon: Icon(Icons.format_list_bulleted),
            label: 'Templates',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            selectedIcon: Icon(Icons.cloud_upload),
            label: 'Uploads',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
