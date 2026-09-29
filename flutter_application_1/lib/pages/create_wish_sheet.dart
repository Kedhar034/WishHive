import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/wish_model.dart';
import '../services/firestore_service.dart';
import '../services/image_storage_service.dart';
import '../services/affiliate_service.dart';
import '../services/wish_image_service.dart';
import '../widgets/image_picker_widget.dart';
import '../providers/providers.dart';
import '../core/constants/app_constants.dart';
import '../widgets/custom_snackbar.dart';
import '../core/theme/app_theme.dart';

/// Bottom sheet for creating/editing a wish.
/// Bottom sheet for creating/editing a wish.
class CreateWishSheet extends ConsumerStatefulWidget {
  final String? initialLink;
  final String? initialTitle;
  final String? initialImageUrl;
  final double? initialCost;
  final List<String>? initialImages;
  final WishModel? wishToEdit;
  final String? preselectedHiveId;   // Pre-select hive (used when friend adds wish)
  final String? friendHiveOwnerId;   // Owner UID when a friend is adding to their hive
  final String? addedByUid;          // Friend's UID (populated when friendHiveOwnerId is set)
  final String? addedByName;         // Friend's display name

  const CreateWishSheet({
    super.key,
    this.initialLink,
    this.initialTitle,
    this.initialImageUrl,
    this.initialCost,
    this.initialImages,
    this.wishToEdit,
    this.preselectedHiveId,
    this.friendHiveOwnerId,
    this.addedByUid,
    this.addedByName,
  });

  @override
  ConsumerState<CreateWishSheet> createState() => _CreateWishSheetState();
}

class _CreateWishSheetState extends ConsumerState<CreateWishSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _subtitleController;
  final _dateController = TextEditingController();
  final _noteController = TextEditingController();
  final _costController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  late final TextEditingController _urlController;
  
  // Track if we are using a network image from metadata
  String? _networkImageUrl;

  File? _selectedImage;
  DateTime? _selectedDate;
  String? _selectedHiveId;
  bool _isLoading = false;
  bool _isNote = false;

  @override
  void initState() {
    super.initState();
    final wish = widget.wishToEdit;
    _isNote = wish?.isNote ?? false;
    
    // Safety check: Don't override 'initialTitle' if editing (though usually mutually exclusive)
    // Priorities: 
    // 1. Existing Wish Data (Edit Mode)
    // 2. Shared/Initial Data (Share Mode)
    // 3. Default/Empty (Create Mode)

    _nameController = TextEditingController(
      text: wish?.name ?? widget.initialTitle ?? ''
    );
    _subtitleController = TextEditingController(
      text: wish?.subtitle ?? '' // Initialize subtitle
    );
    _urlController = TextEditingController(
      text: wish?.link ?? widget.initialLink ?? ''
    );
    
    _noteController.text = wish?.note ?? '';
    _quantityController.text = wish?.quantity.toString() ?? '1';
    // A price scraped from the product page only fills an empty field — it
    // never overwrites a cost the user already entered, or one on an edit.
    _costController.text = wish != null && wish.cost > 0
        ? wish.cost.toString()
        : (widget.initialCost != null && widget.initialCost! > 0
            ? widget.initialCost!.toStringAsFixed(
                widget.initialCost! % 1 == 0 ? 0 : 2)
            : '');
    
    if (wish?.date != null) {
      _selectedDate = wish!.date;
      _dateController.text = '${wish.date!.year}-'
          '${wish.date!.month.toString().padLeft(2, '0')}-'
          '${wish.date!.day.toString().padLeft(2, '0')}';
    }

    _selectedHiveId = wish?.hiveId ?? widget.preselectedHiveId;
    
    // Handle image initialization for Edit Mode
    if (wish != null && wish.imageUrl.isNotEmpty) {
       // If it's a local path, set file. If network, we rely on _networkImageUrl/logic
       if (ImageStorageService.isLocalPath(wish.imageUrl)) {
         _selectedImage = File(wish.imageUrl);
       } else {
         _networkImageUrl = wish.imageUrl;
       }
    } else {
       // Shared Image
       if (widget.initialImageUrl != null && widget.initialImageUrl!.isNotEmpty) {
         if (ImageStorageService.isLocalPath(widget.initialImageUrl!)) {
           _selectedImage = File(widget.initialImageUrl!);
         } else {
           _networkImageUrl = widget.initialImageUrl;
         }
       }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subtitleController.dispose();
    _dateController.dispose();
    _urlController.dispose();
    _noteController.dispose();
    _costController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _onPickImage() async {
    final file = await ImagePickerWidget.pickImage(
      context, 
      defaultImages: AppConstants.defaultImages,
    );
    if (file != null) {
      setState(() {
        _selectedImage = file;
        _networkImageUrl = null; // Clear network image if user picks a local one
      });
    }
  }

  /// Whose `wishes` collection this wish is written to — the hive owner when a
  /// friend is contributing, otherwise the signed-in user.
  String? _wishOwnerId() {
    final owner = widget.friendHiveOwnerId;
    if (owner != null && owner.isNotEmpty) return owner;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _saveWish() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedHiveId == null) {
      CustomSnackBar.showError(context, 'Please select a Hive');
      return;
    }

    setState(() => _isLoading = true);

    // Captured before the sheet pops. Everything below runs after this State is
    // unmounted, and ref.read() throws once that happens — which silently
    // skipped every image upload.
    final uploadService = ref.read(uploadServiceProvider.notifier);

    try {
      String imageUrl = '';
      final name = _nameController.text.trim();
      final subtitle = _isNote ? '' : _subtitleController.text.trim();
      final note = _noteController.text.trim();
      int quantity = 1;
      double cost = 0.0;
      DateTime? date;
      String originalLink = '';
      
      if (!_isNote) {
        // Image Logic:
        if (_selectedImage != null) {
          if (_selectedImage!.path.startsWith('assets/')) {
             imageUrl = _selectedImage!.path;
          } else {
             if (widget.wishToEdit != null && widget.wishToEdit!.imageUrl == _selectedImage!.path) {
                imageUrl = widget.wishToEdit!.imageUrl;
             } else {
                imageUrl = await ImageStorageService.saveImage(_selectedImage!);
             }
          }
        } else if (_networkImageUrl != null && _networkImageUrl!.isNotEmpty) {
          imageUrl = _networkImageUrl!;
        }

        // Auto-image fallback:
        if (imageUrl.isEmpty) {
          imageUrl = WishImageService.getAutoImage(
            name,
            _urlController.text.trim(),
          );
        }
        
        quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
        cost = double.tryParse(_costController.text.trim()) ?? 0.0;
        date = _selectedDate ?? DateTime.now();
        originalLink = _urlController.text.trim();
      }

      // 1. Close the sheet immediately (Optimistic UI)
      if (mounted) {
        Navigator.pop(context);
        CustomSnackBar.showSuccess(context, widget.wishToEdit != null ? 'Wish updated successfully!' : 'Wish created successfully!');
      }

      // 2. Perform the initial save (Fast)
      if (widget.wishToEdit != null) {
        final updatedWish = widget.wishToEdit!.copyWith(
          name: name,
          subtitle: subtitle,
          imageUrl: imageUrl,
          hiveId: _selectedHiveId!,
          date: date,
          quantity: quantity,
          note: note,
          link: originalLink,
          cost: cost,
          isNote: _isNote,
        );
        await FirestoreService().updateWish(updatedWish, ownerId: _wishOwnerId());
        
        // The wish lives in the hive owner's collection, not the uploader's.
        if (!_isNote && _selectedImage != null && !imageUrl.startsWith('http') && !imageUrl.startsWith('assets/')) {
           final ownerId = _wishOwnerId();
           if (ownerId != null) {
             uploadService.addToQueue(updatedWish.id, _selectedImage!, ownerId);
           }
        }
      } else {
        final wish = WishModel(
          id: '',
          name: name,
          subtitle: subtitle,
          imageUrl: imageUrl,
          // Only keep the scraped gallery when the user has not replaced the
          // picture with one of their own.
          images: (_selectedImage == null && widget.initialImages != null)
              ? widget.initialImages!
              : const [],
          hiveId: _selectedHiveId!,
          date: date,
          quantity: quantity,
          note: note,
          link: originalLink,
          cost: cost,
          isNote: _isNote,
          addedByUid: widget.addedByUid ?? '',
          addedByName: widget.addedByName ?? '',
        );

        String newId;
        if (widget.friendHiveOwnerId != null && widget.friendHiveOwnerId!.isNotEmpty) {
          // Friend is adding to someone else's hive
          newId = await FirestoreService().addWishToFriendsHive(widget.friendHiveOwnerId!, wish);
        } else {
          // Owner is adding to their own hive
          newId = await FirestoreService().createWish(wish);
        }

        // The wish lives in the hive owner's collection, not the uploader's.
        if (!_isNote && _selectedImage != null && !imageUrl.startsWith('http') && !imageUrl.startsWith('assets/')) {
           final ownerId = _wishOwnerId();
           if (ownerId != null) {
             uploadService.addToQueue(newId, _selectedImage!, ownerId);
           }
        }
      }

      // 3. Process Affiliate Link in Background (Eventual Consistency)
      if (!_isNote && originalLink.isNotEmpty) {
        // Only check if it's a new link or new wish
        bool shouldCheck = true;
        if (widget.wishToEdit != null && widget.wishToEdit!.link == originalLink) {
          shouldCheck = false;
        }

        if (shouldCheck) {
          final affiliateUrl = await AffiliateService.convertToAffiliateLink(originalLink);
          
          if (affiliateUrl != null && affiliateUrl != originalLink) {
            // we need to update the specific document with the new link
            // For that we need the ID.
            // If it was an edit, we have the ID.
            // If it was a create, we don't have the ID unless we change createWish to return it.
            
            // For now, let's just support it for Edits or if we can find it.
            // To properly support it for Create, we should update FirestoreService.createWish to return the docRef.
            
            // Assuming createWish generates an ID we might miss it here without refactoring service.
            // BUT: The user mostly cares about "Edit" speed right now.
            
            if (widget.wishToEdit != null) {
               final reUpdatedWish = widget.wishToEdit!.copyWith(
                  // We must ensure we use the LATEST values we just saved, 
                  // but effectively we just want to patch the link.
                  // Since we are overwriting, we re-construct it.
                  name: name,
                  subtitle: subtitle,
                  imageUrl: imageUrl,
                  hiveId: _selectedHiveId!,
                  date: date,
                  quantity: quantity,
                  note: note,
                  link: affiliateUrl, // NEW LINK
                  cost: cost,
               );
               await FirestoreService().updateWish(reUpdatedWish, ownerId: _wishOwnerId());
               debugPrint('Background update: Link replaced with affiliate url');
            }
          }
        }
      }

    } catch (e) {
      debugPrint("Background save error: $e");
      if (mounted && _isLoading) {
         setState(() => _isLoading = false);
         CustomSnackBar.showError(context, 'Failed to save wish. Please try again.');
      }
    } finally {
       // Loading state handled in catch or via pop
    }
  }

  Widget _hiveDropdown() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Text('Not signed in');

    final targetUid = widget.friendHiveOwnerId ?? uid;
    final isFriendHive = widget.friendHiveOwnerId != null;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .collection('hives')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text('No hives yet.'),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

        // If it's a friend's hive, lock the selection to that specific hive
        if (isFriendHive) {
          final targetDoc = docs.firstWhere(
            (doc) => doc.id == _selectedHiveId,
            orElse: () => docs.first,
          );
          final hiveTitle = (targetDoc.data() as Map<String, dynamic>)['title'] ?? 'Unnamed Hive';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.hive, color: AppTheme.primaryAmber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Adding to Hive',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      Text(
                        hiveTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final exists = docs.any((doc) => doc.id == _selectedHiveId);

        return DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Select Hive',
            prefixIcon: Icon(Icons.hive),
          ),
          initialValue: exists ? _selectedHiveId : null,
          items: docs.map((doc) {
            return DropdownMenuItem<String>(
              value: doc.id,
              child: Text(
                (doc.data() as Map<String, dynamic>)['title'] ?? 'Unnamed Hive',
              ),
            );
          }).toList(),
          onChanged: (val) => setState(() => _selectedHiveId = val),
          validator: (val) {
            if (val == null) return 'Please select a hive';
            return null;
          },
        );
      },
    );
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
                  widget.wishToEdit != null 
                      ? (_isNote ? 'Edit Note' : 'Edit Wish') 
                      : (_isNote ? 'Create Note' : 'Create Your Wish'),
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),

                // Toggle between Product Wish and Text Note
                if (widget.wishToEdit == null) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false, 
                        label: Text('Product Wish'), 
                        icon: Icon(Icons.shopping_bag_outlined)
                      ),
                      ButtonSegment(
                        value: true, 
                        label: Text('Text Note'), 
                        icon: Icon(Icons.note_alt_outlined)
                      ),
                    ],
                    selected: {_isNote},
                    onSelectionChanged: (val) {
                      setState(() => _isNote = val.first);
                    },
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return theme.colorScheme.primary.withValues(alpha: 0.15);
                        }
                        return Colors.transparent;
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Name / Title
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: _isNote ? 'Note Title' : 'Wish Name',
                    prefixIcon: const Icon(Icons.star_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                if (!_isNote) ...[
                  // Subtitle (New Field)
                  TextFormField(
                    controller: _subtitleController,
                    decoration: const InputDecoration(
                      labelText: 'Subtitle / Short Desc',
                      prefixIcon: Icon(Icons.short_text),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),

                  // Image + Date row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ImagePickerWidget(
                        selectedImage: _selectedImage,
                        initialImageUrl: _selectedImage == null ? _networkImageUrl : null,
                        onImagePicked: _onPickImage,
                        size: 80,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _dateController,
                          decoration: const InputDecoration(
                            labelText: 'Target Date',
                            prefixIcon: Icon(Icons.calendar_month_outlined),
                          ),
                          readOnly: true,
                          onTap: _selectDate,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Cost + Quantity row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _costController,
                          decoration: const InputDecoration(
                            labelText: 'Cost',
                            prefixIcon: Icon(Icons.currency_rupee),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              if (double.tryParse(value.trim()) == null) {
                                return 'Invalid number';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                            prefixIcon: Icon(Icons.numbers),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              if (int.tryParse(value.trim()) == null) {
                                return 'Invalid number';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Note
                TextFormField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: _isNote ? 'Note Content' : 'Note (optional)',
                    prefixIcon: const Icon(Icons.note),
                  ),
                  maxLines: _isNote ? 6 : 2,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) {
                    if (_isNote && (value == null || value.trim().isEmpty)) {
                      return 'Please enter note content';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                if (!_isNote) ...[
                  // Link
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Product Link (optional)',
                      prefixIcon: Icon(Icons.link),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                ],

                // Hive dropdown
                _hiveDropdown(),
                const SizedBox(height: 24),

                // Create/Update button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveWish,
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(widget.wishToEdit != null 
                            ? (_isNote ? 'Update Note' : 'Update Wish') 
                            : (_isNote ? 'Create Note' : 'Create Wish')),
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
}
