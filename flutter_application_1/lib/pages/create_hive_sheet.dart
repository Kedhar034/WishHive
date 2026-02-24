import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/hive_model.dart';
import '../services/firestore_service.dart';
import '../services/image_storage_service.dart';
import '../widgets/image_picker_widget.dart';
import '../providers/providers.dart';
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
    final result = await ImagePickerWidget.pickImage(context);
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
      );

      if (widget.hiveToEdit == null) {
        await ref.read(firestoreServiceProvider).createHive(hive);
      } else {
        await ref.read(firestoreServiceProvider).updateHive(hive);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
              Text(
                widget.hiveToEdit == null ? 'Create New Hive' : 'Edit Hive',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
                onSelectionChanged: (set) => setState(() => _privacy = set.first),
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
