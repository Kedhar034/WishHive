import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/hive_card.dart';
import '../widgets/hive_title.dart';
import '../core/theme/app_theme.dart';
import '../widgets/color_wheel_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/hive_model.dart';
import '../services/image_storage_service.dart';
import '../widgets/image_picker_widget.dart';
import '../providers/providers.dart';
import '../core/constants/app_constants.dart';
import '../widgets/custom_snackbar.dart';
import 'hive_access_page.dart';

class CreateHiveSheet extends ConsumerStatefulWidget {
  final HiveModel? hiveToEdit;

  const CreateHiveSheet({super.key, this.hiveToEdit});

  @override
  ConsumerState<CreateHiveSheet> createState() => _CreateHiveSheetState();
}

class _CreateHiveSheetState extends ConsumerState<CreateHiveSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  File? _selectedImage;
  String? _cardColor;
  String? _networkImageUrl;
  HivePrivacy _privacy = HivePrivacy.private;
  List<String> _allowedViewerIds = [];
  List<String> _allowedEditorIds = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.hiveToEdit?.title ?? '');
    _noteController = TextEditingController(text: widget.hiveToEdit?.note ?? '');
    _privacy = widget.hiveToEdit?.privacy ?? HivePrivacy.private;
    _allowedViewerIds = widget.hiveToEdit?.allowedViewerIds ?? [];
    _allowedEditorIds = widget.hiveToEdit?.allowedEditorIds ?? [];
    
    if (widget.hiveToEdit?.imageUrl != null && widget.hiveToEdit!.imageUrl.isNotEmpty) {
      if (ImageStorageService.isLocalPath(widget.hiveToEdit!.imageUrl)) {
        _selectedImage = File(widget.hiveToEdit!.imageUrl);
      } else {
        _networkImageUrl = widget.hiveToEdit!.imageUrl;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await ImagePickerWidget.pickImage(
      context,
      defaultImages: AppConstants.defaultImages,
    );
    if (result != null) {
      setState(() {
        _selectedImage = result;
        _networkImageUrl = null;
      });
    }
  }

  void _onAccessSaved(Set<String> viewers, Set<String> editors) {
    setState(() {
      _allowedViewerIds = viewers.toList();
      _allowedEditorIds = editors.toList();
    });
  }

  Future<void> _saveHive() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      String imageUrl = _networkImageUrl ?? '';
      if (_selectedImage != null) {
        imageUrl = _selectedImage!.path;
      }

      final hive = (widget.hiveToEdit ?? HiveModel(
        id: '',
        title: '',
        ownerId: user.uid,
        ownerDisplayName: user.displayName ?? 'My Hive',
      )).copyWith(
        title: _titleController.text,
        note: _noteController.text,
        imageUrl: imageUrl,
        privacy: _privacy,
        allowedViewerIds: _allowedViewerIds,
        allowedEditorIds: _allowedEditorIds,
        cardColor: _cardColor,
      );

      if (widget.hiveToEdit == null) {
        await ref.read(firestoreServiceProvider).createHive(hive);
      } else {
        await ref.read(firestoreServiceProvider).updateHive(hive);
      }

      if (!mounted) return;
      CustomSnackBar.showSuccess(context, widget.hiveToEdit == null ? 'Hive created successfully!' : 'Hive updated successfully!');
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Failed to save hive: $e');
      if (mounted) {
        CustomSnackBar.showError(context, 'Failed to save hive. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// The colour the card is showing right now, whatever its source.
  Color get _currentColor =>
      AppTheme.colorFor(_resolvedColorKey, widget.hiveToEdit?.id ?? '');

  Future<void> _openColorWheel() async {
    var picked = _currentColor;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HiveTitle('Card colour', size: 30),
              const SizedBox(height: 18),
              ColorWheelPicker(
                initial: picked,
                onChanged: (c) => setSheetState(() => picked = c),
              ),
              const SizedBox(height: 20),
              // The card itself is the preview, so the choice is judged
              // against the thing it actually affects.
              IgnorePointer(
                child: HiveCard(
                  title: _titleController.text.trim().isEmpty
                      ? 'Your hive'
                      : _titleController.text.trim(),
                  items: widget.hiveToEdit?.itemCount ?? 0,
                  price: widget.hiveToEdit?.totalCost ?? 0,
                  imageUrl: _networkImageUrl ?? '',
                  colorKey: AppTheme.keyForColor(picked),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Use this colour'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _cardColor = AppTheme.keyForColor(picked));
    }
  }

  /// The key currently in force: what was picked in this sheet, or the colour
  /// the hive already shows, so the ring starts on the right swatch.
  String? get _resolvedColorKey {
    if (_cardColor != null) return _cardColor;
    final existing = widget.hiveToEdit;
    if (existing == null) return null;
    if (existing.cardColor != null) return existing.cardColor;
    final shown = AppTheme.tintFor(existing.id);
    for (final entry in AppTheme.namedTints.entries) {
      if (entry.value == shown) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: HiveTitle(
                  widget.hiveToEdit == null ? 'New hive' : 'Edit hive',
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),

              // Live preview of the card, rebuilt straight from the title
              // field so nothing extra has to be tracked in state.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _titleController,
                builder: (context, value, _) {
                  final preview = value.text.trim();
                  return Stack(
                    children: [
                      HiveCard(
                        title: preview.isEmpty ? 'Your hive' : preview,
                        items: widget.hiveToEdit?.itemCount ?? 0,
                        price: widget.hiveToEdit?.totalCost ?? 0,
                        imageUrl: _networkImageUrl ?? '',
                        tintSeed: widget.hiveToEdit?.id ?? '',
                        colorKey: _resolvedColorKey,
                      ),
                      Positioned(
                        left: 16,
                        bottom: 10,
                        child: Text(
                          'Live preview of your card',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 12,
                            color: AppTheme.muted.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Card colour', style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final entry in AppTheme.namedTints.entries)
                      _ColorRing(
                        color: entry.value,
                        selected: _resolvedColorKey == entry.key,
                        onTap: () => setState(() => _cardColor = entry.key),
                      ),
                    // Anything beyond the presets, picked from the wheel.
                    _ColorRing(
                      color: _currentColor,
                      selected: _resolvedColorKey != null &&
                          !AppTheme.namedTints.containsKey(_resolvedColorKey),
                      showWheel: true,
                      onTap: _openColorWheel,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ImagePickerWidget(
                selectedImage: _selectedImage,
                initialImageUrl: _networkImageUrl,
                onImagePicked: _pickImage,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Hive Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Privacy Setting', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 10),
              SegmentedButton<HivePrivacy>(
                segments: const [
                  ButtonSegment(value: HivePrivacy.private, label: Text('Private'), icon: Icon(Icons.lock_outline)),
                  ButtonSegment(value: HivePrivacy.friends, label: Text('Friends'), icon: Icon(Icons.people_outline)),
                  ButtonSegment(value: HivePrivacy.specific, label: Text('Specific'), icon: Icon(Icons.person_add_outlined)),
                ],
                selected: {_privacy},
                onSelectionChanged: (set) => setState(() {
                  _privacy = set.first;
                  if (_privacy != HivePrivacy.specific) {
                    _allowedViewerIds = [];
                    _allowedEditorIds = [];
                  }
                }),
              ),
              if (_privacy == HivePrivacy.specific) ...[
                const SizedBox(height: 16),
                ListTile(
                  tileColor: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Manage Access'),
                  subtitle: Text('${_allowedViewerIds.length} can view • ${_allowedEditorIds.length} can edit'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HiveAccessPage(
                          initialViewerIds: Set.from(_allowedViewerIds),
                          initialEditorIds: Set.from(_allowedEditorIds),
                          onSave: _onAccessSaved,
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveHive,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  child: _isSaving 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Hive', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A colour swatch that shows selection as a ring around it rather than a tick
/// on top, so the colour itself is never obscured.
class _ColorRing extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// Marks the swatch that opens the wheel rather than setting a preset.
  final bool showWheel;

  const _ColorRing({
    required this.color,
    required this.selected,
    required this.onTap,
    this.showWheel = false,
  });

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.onSurface;

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? ring : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: showWheel
                ? Icon(Icons.tune_rounded,
                    size: 16, color: AppTheme.onColor(color))
                : null,
          ),
        ),
      ),
    );
  }
}
