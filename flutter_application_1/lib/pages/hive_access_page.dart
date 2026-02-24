import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/avatar_image.dart';

class HiveAccessPage extends ConsumerStatefulWidget {
  final Set<String> initialViewerIds;
  final Set<String> initialEditorIds;
  final void Function(Set<String> viewers, Set<String> editors) onSave;

  const HiveAccessPage({
    super.key,
    required this.initialViewerIds,
    required this.initialEditorIds,
    required this.onSave,
  });

  @override
  ConsumerState<HiveAccessPage> createState() => _HiveAccessPageState();
}

class _HiveAccessPageState extends ConsumerState<HiveAccessPage> {
  late Set<String> _viewerIds;
  late Set<String> _editorIds;

  @override
  void initState() {
    super.initState();
    _viewerIds = Set.from(widget.initialViewerIds);
    _editorIds = Set.from(widget.initialEditorIds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserStreamProvider).value;
    final friends = user?.friends ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Access'),
        actions: [
          TextButton.icon(
            onPressed: () {
              widget.onSave(_viewerIds, _editorIds);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check),
            label: const Text('Save'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryAmber,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: friends.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline,
                      size: 64,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.25)),
                  const SizedBox(height: 16),
                  Text('No friends yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(height: 8),
                  Text('Add friends to share this hive',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            )
          : Column(
              children: [
                // Header info
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAmber.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppTheme.primaryAmber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'View = friend can see your wishes.\nEdit = friend can also add wishes.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

                // Column headers
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 5,
                        child: Text('Friend',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.visibility_outlined, size: 15),
                            SizedBox(width: 4),
                            Text('View',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.edit_outlined, size: 15),
                            SizedBox(width: 4),
                            Text('Edit',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Friends list
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: friends.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      final canView = _viewerIds.contains(friend.uid);
                      final canEdit = _editorIds.contains(friend.uid);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            // Avatar + Name
                            Expanded(
                              flex: 5,
                              child: Row(
                                children: [
                            AvatarImage(
                                  url: friend.photoUrl,
                                  radius: 18,
                                ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          friend.displayName,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          friend.email,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: theme.colorScheme
                                                  .onSurfaceVariant),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // View toggle
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: _AccessCircle(
                                  active: canView,
                                  activeColor: theme.colorScheme.secondary,
                                  onTap: () => setState(() {
                                    if (canView) {
                                      _viewerIds.remove(friend.uid);
                                      _editorIds.remove(friend.uid);
                                    } else {
                                      _viewerIds.add(friend.uid);
                                    }
                                  }),
                                ),
                              ),
                            ),

                            // Edit toggle
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: _AccessCircle(
                                  active: canEdit,
                                  activeColor: theme.colorScheme.primary,
                                  onTap: () => setState(() {
                                    if (canEdit) {
                                      _editorIds.remove(friend.uid);
                                    } else {
                                      _editorIds.add(friend.uid);
                                      _viewerIds.add(friend.uid);
                                    }
                                  }),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _AccessCircle extends StatelessWidget {
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _AccessCircle({
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? activeColor : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: active
                ? activeColor
                : theme.colorScheme.outline.withValues(alpha: 0.35),
            width: 2,
          ),
        ),
        child: active
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}
