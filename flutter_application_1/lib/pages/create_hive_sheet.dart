import 'dart:io';
import 'package:flutter/material.dart';
import '../models/hive_model.dart';
import '../services/firestore_service.dart';
import '../services/image_storage_service.dart';
import '../widgets/image_picker_widget.dart';
import '../core/constants/app_constants.dart';

/// Bottom sheet for creating/editing a hive.
class CreateHiveSheet extends StatefulWidget {
  final HiveModel? hiveToEdit;

  const CreateHiveSheet({super.key, this.hiveToEdit});

  @override
  State<CreateHiveSheet> createState() => _CreateHiveSheetState();
}

class _CreateHiveSheetState extends State<CreateHiveSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  File? _selectedImage;
  String? _networkImageUrl;
  HivePrivacy _privacy = HivePrivacy.private;
  bool _isLoading = false;

  bool get _isEditing => widget.hiveToEdit != null;

  @override
  void initState() {
    super.initState();
    final hive = widget.hiveToEdit;
    _titleController = TextEditingController(text: hive?.title ?? '');
    _noteController = TextEditingController(text: hive?.note ?? '');
    if (hive != null) {
      _privacy = hive.privacy;
      if (hive.imageUrl.isNotEmpty) {
        if (ImageStorageService.isLocalPath(hive.imageUrl)) {
          // Check if it's a file or asset
          if (hive.imageUrl.startsWith('assets/')) {
            _networkImageUrl = hive.imageUrl; // Treat asset path as string url for now
          } else {
            _selectedImage = File(hive.imageUrl);
          }
        } else {
          _networkImageUrl = hive.imageUrl;
        }
      }
    } else {
      // New hive: pick random default
      _networkImageUrl = (List<String>.from(AppConstants.hiveImages)..shuffle()).first;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveHive() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      String imageUrl = '';

      if (_selectedImage != null) {
        if (_selectedImage!.path.startsWith('assets/')) {
          imageUrl = _selectedImage!.path;
        } else {
          // Don't re-save if it's the same file as before
          if (_isEditing && widget.hiveToEdit!.imageUrl == _selectedImage!.path) {
            imageUrl = widget.hiveToEdit!.imageUrl;
          } else {
            imageUrl = await ImageStorageService.saveImage(_selectedImage!);
          }
        }
      } else if (_networkImageUrl != null && _networkImageUrl!.isNotEmpty) {
        imageUrl = _networkImageUrl!;
      }

      if (_isEditing) {
        final updatedHive = widget.hiveToEdit!.copyWith(
          title: _titleController.text.trim(),
          imageUrl: imageUrl,
          note: _noteController.text.trim(),
          privacy: _privacy,
        );
        await FirestoreService().updateHive(updatedHive);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hive updated successfully!')),
          );
        }
      } else {
        final hive = HiveModel(
          id: '',
          title: _titleController.text.trim(),
          imageUrl: imageUrl,
          note: _noteController.text.trim(),
          privacy: _privacy,
        );
        await FirestoreService().createHive(hive);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hive created successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save hive: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onPickImage() async {
    final file = await ImagePickerWidget.pickImage(
      context,
      defaultImages: AppConstants.hiveImages, // Use Hive-specific defaults
    );
    if (file != null) {
      setState(() {
        _selectedImage = file;
        _networkImageUrl = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
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
                  _isEditing ? 'Edit Hive' : 'Create Your Hive',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),

                // Image picker
                ImagePickerWidget(
                  selectedImage: _selectedImage,
                  initialImageUrl: _networkImageUrl, // Can be http or assets/
                  onImagePicked: _onPickImage,
                  size: 140,
                ),
                const SizedBox(height: 24),

                // Title
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Hive Name',
                    prefixIcon: Icon(Icons.hive),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name for your hive';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Privacy selection
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Privacy',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _buildPrivacyOption(
                            theme,
                            title: 'Public',
                            subtitle: 'Visible to everyone',
                            icon: Icons.public,
                            value: HivePrivacy.public,
                          ),
                          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
                          _buildPrivacyOption(
                            theme,
                            title: 'Friends Only',
                            subtitle: 'Visible to your friends',
                            icon: Icons.people,
                            value: HivePrivacy.friends,
                          ),
                          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
                          _buildPrivacyOption(
                            theme,
                            title: 'Private',
                            subtitle: 'Visible only to you',
                            icon: Icons.lock,
                            value: HivePrivacy.private,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Note
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 28),

                // Create button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveHive,
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEditing ? 'Update Hive' : 'Create Hive'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildPrivacyOption(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required IconData icon,
    required HivePrivacy value,
  }) {
    final isSelected = _privacy == value;
    return InkWell(
      onTap: () => setState(() => _privacy = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? theme.colorScheme.primary : Colors.grey,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
