import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../domain/models.dart';
import '../../ui/tokens.dart';

class NewInspectionSheet extends ConsumerStatefulWidget {
  const NewInspectionSheet({super.key});

  @override
  ConsumerState<NewInspectionSheet> createState() => _NewInspectionSheetState();
}

class _NewInspectionSheetState extends ConsumerState<NewInspectionSheet> {
  final _siteNameController = TextEditingController();
  final _siteAddressController = TextEditingController();
  late final TextEditingController _inspectorNameController;

  String? _selectedTemplateId;
  var _recordGps = true;
  var _isStarting = false;

  @override
  void initState() {
    super.initState();
    _inspectorNameController = TextEditingController(
      text: ref.read(inspectorNameProvider),
    );
  }

  @override
  void dispose() {
    _siteNameController.dispose();
    _siteAddressController.dispose();
    _inspectorNameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final templateId = _selectedTemplateId;
    final siteName = _siteNameController.text.trim();
    final inspectorName = _inspectorNameController.text.trim();

    if (templateId == null || siteName.isEmpty || inspectorName.isEmpty) return;

    setState(() => _isStarting = true);

    final res = await ref.read(inspectionRepositoryProvider).startInspection(
          templateId: templateId,
          siteName: siteName,
          siteAddress: _siteAddressController.text.trim().isNotEmpty
              ? _siteAddressController.text.trim()
              : null,
          inspectorName: inspectorName,
          startGpsStatus: _recordGps ? GpsFixStatus.none : null,
        );

    if (!mounted) return;

    if (res.isOk) {
      final inspection = res.valueOrNull!;
      Navigator.of(context).pop();
      unawaited(context.push('/inspections/${inspection.id}'));
    } else {
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.errorOrNull?.message ?? 'Failed to start inspection')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(templatesStreamProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: EdgeInsets.all(tokens.space24),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.radiusCard),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'New Inspection',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.text,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SizedBox(height: tokens.space16),

              // Template picker
              Text('Checklist Template', style: theme.textTheme.labelLarge),
              SizedBox(height: tokens.space8),
              templatesAsync.when(
                data: (List<Template> templates) {
                  if (templates.isEmpty) {
                    return Text('No templates found', style: theme.textTheme.bodySmall);
                  }
                  _selectedTemplateId ??= templates.first.id;
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedTemplateId,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: tokens.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusCard),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                    ),
                    items: templates.map((Template tpl) {
                      return DropdownMenuItem<String>(
                        value: tpl.id,
                        child: Text(
                          tpl.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (String? val) {
                      if (val != null) setState(() => _selectedTemplateId = val);
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (Object _, StackTrace _) => const Text('Failed to load templates'),
              ),
              SizedBox(height: tokens.space16),

              // Site Name
              Text('Site / Facility Name', style: theme.textTheme.labelLarge),
              SizedBox(height: tokens.space8),
              TextField(
                controller: _siteNameController,
                decoration: InputDecoration(
                  hintText: 'e.g. West Distribution Depot',
                  filled: true,
                  fillColor: tokens.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusCard),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: tokens.space16),

              // Site Address
              Text('Address / Sector (Optional)', style: theme.textTheme.labelLarge),
              SizedBox(height: tokens.space8),
              TextField(
                controller: _siteAddressController,
                decoration: InputDecoration(
                  hintText: 'e.g. Dock 4, Bay 12',
                  filled: true,
                  fillColor: tokens.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusCard),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                ),
              ),
              SizedBox(height: tokens.space16),

              // Inspector Name
              Text('Inspector Name', style: theme.textTheme.labelLarge),
              SizedBox(height: tokens.space8),
              TextField(
                controller: _inspectorNameController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: tokens.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusCard),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: tokens.space16),

              // GPS Location toggle
              SwitchListTile(
                title: Text('Record GPS location for site', style: theme.textTheme.titleMedium),
                subtitle: Text('Records coordinates and accuracy', style: theme.textTheme.bodySmall),
                value: _recordGps,
                activeThumbColor: tokens.primary,
                onChanged: (val) => setState(() => _recordGps = val),
                contentPadding: EdgeInsets.zero,
              ),
              SizedBox(height: tokens.space24),

              // Start button
              FilledButton(
                onPressed: _siteNameController.text.trim().isNotEmpty &&
                        _inspectorNameController.text.trim().isNotEmpty &&
                        _selectedTemplateId != null &&
                        !_isStarting
                    ? _start
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(tokens.answerButtonHeight),
                  backgroundColor: tokens.primary,
                ),
                child: _isStarting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Start Walk-Round'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
