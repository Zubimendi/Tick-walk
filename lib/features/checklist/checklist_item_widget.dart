import 'dart:io';

import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/answer_buttons.dart';
import '../../ui/widgets/severity_chips.dart';

class ChecklistItemWidget extends StatefulWidget {
  const ChecklistItemWidget({
    super.key,
    required this.item,
    required this.photoCount,
    required this.isReadOnly,
    required this.onAnswerChanged,
    required this.onAddPhoto,
    this.attachments = const [],
    this.onPhotoTap,
  });

  final InspectionItem item;
  final int photoCount;
  final bool isReadOnly;
  final Future<void> Function({
    ItemResponse? response,
    Severity? severity,
    String? textValue,
    double? numberValue,
    String? note,
  }) onAnswerChanged;
  final VoidCallback onAddPhoto;
  /// Photos already attached to this item — drives the photo strip in the fail panel.
  final List<Attachment> attachments;
  /// Called when user taps a thumbnail; passes the attachment ID.
  final void Function(String attachmentId)? onPhotoTap;

  @override
  State<ChecklistItemWidget> createState() => _ChecklistItemWidgetState();
}

class _ChecklistItemWidgetState extends State<ChecklistItemWidget> {
  late final TextEditingController _noteController;
  late final TextEditingController _textController;
  late final TextEditingController _numberController;
  var _isNoteExpanded = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.item.note);
    _textController = TextEditingController(text: widget.item.textValue);
    _numberController = TextEditingController(
      text: widget.item.numberValue != null ? widget.item.numberValue.toString() : '',
    );
    _isNoteExpanded = widget.item.note != null && widget.item.note!.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant ChecklistItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.note != widget.item.note &&
        _noteController.text != widget.item.note) {
      _noteController.text = widget.item.note ?? '';
    }
    if (oldWidget.item.textValue != widget.item.textValue &&
        _textController.text != widget.item.textValue) {
      _textController.text = widget.item.textValue ?? '';
    }
    if (oldWidget.item.numberValue != widget.item.numberValue) {
      final newText = widget.item.numberValue != null
          ? widget.item.numberValue.toString()
          : '';
      if (_numberController.text != newText) {
        _numberController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _textController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final item = widget.item;
    final isFail = item.response == ItemResponse.fail;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: tokens.screenPadding,
        vertical: tokens.space4,
      ),
      padding: EdgeInsets.all(tokens.space16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusCard),
        border: Border.all(
          color: isFail ? tokens.fail.withValues(alpha: 0.4) : tokens.border,
          width: isFail ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Prompt & Requirement badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.prompt,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
              if (item.required)
                Container(
                  margin: EdgeInsets.only(left: tokens.space8),
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.space8,
                    vertical: tokens.space4,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.border.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(tokens.radiusChip),
                  ),
                  child: Text(
                    'Required',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: tokens.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: tokens.space12),

          // Answer Control
          if (item.itemType == ItemType.passFail)
            AnswerButtons(
              selected: item.response?.value,
              enabled: !widget.isReadOnly,
              onChanged: (val) {
                final newResp = ItemResponse.fromString(val);
                widget.onAnswerChanged(
                  response: newResp,
                  severity: newResp == ItemResponse.fail ? (item.severity ?? Severity.medium) : null,
                );
              },
            )
          else if (item.itemType == ItemType.text)
            TextField(
              controller: _textController,
              enabled: !widget.isReadOnly,
              decoration: InputDecoration(
                hintText: 'Enter observation / notes',
                filled: true,
                fillColor: tokens.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusCard),
                  borderSide: BorderSide(color: tokens.border),
                ),
              ),
              onChanged: (text) {
                widget.onAnswerChanged(textValue: text);
              },
            )
          else if (item.itemType == ItemType.number)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _numberController,
                    enabled: !widget.isReadOnly,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: InputDecoration(
                      hintText: 'Enter value',
                      filled: true,
                      fillColor: tokens.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusCard),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                    ),
                    onChanged: (val) {
                      final parsed = double.tryParse(val.trim());
                      widget.onAnswerChanged(numberValue: parsed);
                    },
                  ),
                ),
                if (item.unit != null) ...[
                  SizedBox(width: tokens.space12),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.space12,
                      vertical: tokens.space12,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.border.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(tokens.radiusCard),
                    ),
                    child: Text(
                      item.unit!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),

          // Fail Panel (Expanded on Fail)
          if (isFail) ...[
            SizedBox(height: tokens.space16),
            Container(
              padding: EdgeInsets.all(tokens.space12),
              decoration: BoxDecoration(
                color: tokens.fail.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(tokens.radiusCard),
                border: Border.all(color: tokens.fail.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Severity Chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Severity',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: tokens.fail,
                        ),
                      ),
                      if (item.photoRequiredOnFail)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.space8,
                            vertical: tokens.space4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.photoCount > 0
                                ? tokens.pass.withValues(alpha: 0.15)
                                : tokens.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(tokens.radiusChip),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.photoCount > 0 ? Icons.check : Icons.camera_alt,
                                size: 12,
                                color: widget.photoCount > 0 ? tokens.pass : tokens.warning,
                              ),
                              SizedBox(width: tokens.space4),
                              Text(
                                widget.photoCount > 0 ? 'Photo attached' : 'Photo required',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: widget.photoCount > 0 ? tokens.pass : tokens.warning,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: tokens.space8),
                  SeverityChips(
                    selected: item.severity?.value,
                    enabled: !widget.isReadOnly,
                    onChanged: (sevVal) {
                      widget.onAnswerChanged(
                        severity: Severity.fromString(sevVal),
                      );
                    },
                  ),
                  SizedBox(height: tokens.space12),

                  // Finding Note
                  TextField(
                    controller: _noteController,
                    enabled: !widget.isReadOnly,
                    decoration: InputDecoration(
                      hintText: 'Describe finding / defect reason',
                      filled: true,
                      fillColor: tokens.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusCard),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                    ),
                    onChanged: (val) {
                      widget.onAnswerChanged(note: val);
                    },
                  ),
                  SizedBox(height: tokens.space12),

                  // Photo strip
                  if (widget.attachments.isNotEmpty) ...[
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.attachments.length,
                        separatorBuilder: (context, index) => SizedBox(width: tokens.space8),
                        itemBuilder: (context, index) {
                          final att = widget.attachments[index];
                          final hasThumb = att.thumbPath != null &&
                              att.thumbPath!.isNotEmpty &&
                              File(att.thumbPath!).existsSync();
                          final hasLocal = att.localPath != null &&
                              att.localPath!.isNotEmpty &&
                              File(att.localPath!).existsSync();

                          return Semantics(
                            button: true,
                            label: 'Photo evidence thumbnail ${index + 1}',
                            child: InkWell(
                              onTap: () => widget.onPhotoTap?.call(att.id),
                              borderRadius: BorderRadius.circular(tokens.radiusCard),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(tokens.radiusCard),
                                  border: Border.all(color: tokens.border),
                                  color: tokens.surface,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (hasThumb || hasLocal)
                                      Image.file(
                                        File(hasThumb ? att.thumbPath! : att.localPath!),
                                        fit: BoxFit.cover,
                                        cacheWidth: 144,
                                        errorBuilder: (context, error, stackTrace) => Center(
                                          child: Icon(Icons.broken_image,
                                              size: 24, color: tokens.textSecondary),
                                        ),
                                      )
                                    else
                                      Center(
                                        child: Icon(Icons.photo,
                                            size: 24, color: tokens.textSecondary),
                                      ),
                                    // Status icon badge overlay
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          att.isUploaded
                                              ? Icons.cloud_done
                                              : Icons.access_time,
                                          size: 12,
                                          color: att.isUploaded
                                              ? tokens.pass
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: tokens.space12),
                  ],

                  // Photo action button
                  OutlinedButton.icon(
                    onPressed: !widget.isReadOnly ? widget.onAddPhoto : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      widget.photoCount > 0
                          ? 'Add Evidence Photo (${widget.photoCount})'
                          : 'Add Evidence Photo',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.fail,
                      side: BorderSide(color: tokens.fail),
                      minimumSize: Size.fromHeight(tokens.minTouchTarget),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (item.itemType == ItemType.passFail) ...[
            // Optional note toggle for Pass / NA
            if (!_isNoteExpanded)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: !widget.isReadOnly
                      ? () => setState(() => _isNoteExpanded = true)
                      : null,
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('Add observation note'),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                  ),
                ),
              )
            else ...[
              SizedBox(height: tokens.space8),
              TextField(
                controller: _noteController,
                enabled: !widget.isReadOnly,
                decoration: InputDecoration(
                  hintText: 'Add note',
                  filled: true,
                  fillColor: tokens.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusCard),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                ),
                onChanged: (val) {
                  widget.onAnswerChanged(note: val);
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
