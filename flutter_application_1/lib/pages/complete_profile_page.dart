import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/image_storage_service.dart';
import '../widgets/image_selection_sheet.dart';
import 'home_page.dart';
import '../core/constants/app_constants.dart';

class CompleteProfilePage extends StatefulWidget {
  final User? firebaseUser;

  const CompleteProfilePage({super.key, this.firebaseUser});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _firestoreService = FirestoreService();

  File? _selectedFile;
  String? _selectedAvatarUrl;
  
  bool _isLoading = false;
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = false;
  Timer? _debounce;
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    // Pre-fill if firebase user has photo
    if (widget.firebaseUser?.photoURL != null) {
      _selectedAvatarUrl = widget.firebaseUser!.photoURL;
    } else {
      // Pick a random default avatar
      _selectedAvatarUrl = (List<String>.from(AppConstants.avatarImages)..shuffle()).first;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    setState(() {
      _usernameError = null;
      _isUsernameAvailable = false;
    });

    if (value.trim().length < 3) {
       setState(() => _usernameError = 'Username must be at least 3 characters');
       return;
    }

    setState(() => _isCheckingUsername = true);

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final isAvailable = await _firestoreService.isUsernameAvailable(value);
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = isAvailable;
          if (!isAvailable) {
            _usernameError = 'Username is already taken';
          }
        });
      }
    });
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ImageSelectionSheet(
        onImageSelected: (file) {
          setState(() {
            _selectedFile = file;
            _selectedAvatarUrl = null;
          });
        },
        onAvatarSelected: (url) {
          setState(() {
            _selectedAvatarUrl = url;
            _selectedFile = null;
          });
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_usernameError != null || (!_isUsernameAvailable && !_isLoading)) return; // Wait for check
    // Wait if still checking?
    if (_isCheckingUsername) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checking username availability...')));
        return;
    }
    
    final uid = widget.firebaseUser?.uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      String? photoUrl = _selectedAvatarUrl;

      // Upload local image if selected
      if (_selectedFile != null) {
        photoUrl = await ImageStorageService.compressAndUploadImage(_selectedFile!, uid);
      }

      // If no photo selected, use fallback or existing
      photoUrl ??= AppConstants.fallbackImage;

      await _firestoreService.updateUser(UserModel(
        uid: uid,
        email: widget.firebaseUser?.email ?? '',
        displayName: _usernameController.text.trim(), // Use username as display name primarily for now
        username: _usernameController.text.trim().toLowerCase(),
        photoUrl: photoUrl,
      ));

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBtnEnabled = !_isLoading && _isUsernameAvailable && (_selectedFile != null || _selectedAvatarUrl != null);

    return Scaffold(
      appBar: AppBar(title: const Text('Complete Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                'Tell us about yourself',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a unique username and a profile picture.',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // Avatar Selection
              Center(
                child: GestureDetector(
                  onTap: _showImagePicker,
                  child: Stack(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[200],
                          border: Border.all(color: theme.colorScheme.primary, width: 2),
                          image: _selectedFile != null
                              ? DecorationImage(image: FileImage(_selectedFile!), fit: BoxFit.cover)
                              : _selectedAvatarUrl != null
                                  ? DecorationImage(
                                      image: _selectedAvatarUrl!.startsWith('assets/')
                                          ? AssetImage(_selectedAvatarUrl!) as ImageProvider
                                          : NetworkImage(_selectedAvatarUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                        ),
                        child: (_selectedFile == null && _selectedAvatarUrl == null)
                            ? Icon(Icons.person, size: 60, color: Colors.grey[400])
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Username Field
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.alternate_email),
                  suffixIcon: _isCheckingUsername
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : _isUsernameAvailable
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                  errorText: _usernameError,
                ),
                onChanged: _onUsernameChanged,
              ),
              const SizedBox(height: 40),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: isBtnEnabled ? _submit : null,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
