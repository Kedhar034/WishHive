import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/providers.dart';
import 'custom_snackbar.dart';

/// Moderation report sheet. Required by Google Play's user-generated content
/// policy for apps where people can see each other's content.
class ReportSheet extends ConsumerStatefulWidget {
  /// 'hive', 'wish' or 'user'.
  final String targetType;
  final String targetId;
  final String targetOwnerUid;
  final String targetLabel;

  const ReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.targetOwnerUid,
    required this.targetLabel,
  });

  static Future<void> show(
    BuildContext context, {
    required String targetType,
    required String targetId,
    required String targetOwnerUid,
    required String targetLabel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportSheet(
        targetType: targetType,
        targetId: targetId,
        targetOwnerUid: targetOwnerUid,
        targetLabel: targetLabel,
      ),
    );
  }

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  static const _reasons = <String, String>{
    'spam': 'Spam or scam',
    'harassment': 'Harassment or bullying',
    'hate': 'Hate speech',
    'sexual': 'Nudity or sexual content',
    'violence': 'Violence or dangerous content',
    'impersonation': 'Impersonation',
    'ip': 'Intellectual property',
    'other': 'Something else',
  };

  String? _reason;
  final _detailsController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null || _sending) return;
    setState(() => _sending = true);

    try {
      await ref.read(firestoreServiceProvider).reportContent(
            targetType: widget.targetType,
            targetId: widget.targetId,
            targetOwnerUid: widget.targetOwnerUid,
            reason: _reason!,
            details: _detailsController.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      CustomSnackBar.showSuccess(
          context, 'Report sent. Thank you — we review every report.');
    } catch (e) {
      debugPrint('Report failed: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      CustomSnackBar.showError(context, 'Could not send the report. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Report', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                widget.targetLabel,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 18),
              Text('Why are you reporting this?',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ..._reasons.entries.map((e) {
                final selected = _reason == e.key;
                return ListTile(
                  onTap: _sending ? null : () => setState(() => _reason = e.key),
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? AppTheme.primaryAmber
                        : theme.colorScheme.outline,
                    size: 22,
                  ),
                  title: Text(e.value, style: const TextStyle(fontSize: 14)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  horizontalTitleGap: 8,
                );
              }),
              const SizedBox(height: 8),
              TextField(
                controller: _detailsController,
                enabled: !_sending,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: 'Anything else? (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _reason == null || _sending ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  child: _sending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit report',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
