import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';

final avatarBytesProvider = FutureProvider<Uint8List?>((ref) async {
  final user = ref.watch(sessionProvider).user;
  if (user == null || !user.hasAvatar) {
    return null;
  }
  return ref.read(authRepositoryProvider).downloadAvatar();
});

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.bytes,
    this.size = 72,
    this.showEdit = false,
    this.onTap,
    this.loading = false,
  });

  final String name;
  final Uint8List? bytes;
  final double size;
  final bool showEdit;
  final VoidCallback? onTap;
  final bool loading;

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'N' : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final image = bytes == null
        ? null
        : MemoryImage(bytes!);
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: image == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.purple, AppColors.pink],
              )
            : null,
        image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
        border: Border.all(color: AppColors.card, width: 3),
        boxShadow: const [
          BoxShadow(color: AppColors.overlay, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: image == null
          ? Text(
              _initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38,
              ),
            )
          : null,
    );

    return Semantics(
      button: onTap != null,
      label: showEdit ? 'Change profile photo' : 'Profile photo',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                if (loading)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 3),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                if (showEdit)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.purple,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SessionAvatar extends ConsumerWidget {
  const SessionAvatar({
    super.key,
    this.size = 56,
    this.showEdit = false,
    this.onTap,
    this.previewBytes,
    this.loading = false,
  });

  final double size;
  final bool showEdit;
  final VoidCallback? onTap;
  final Uint8List? previewBytes;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(sessionProvider).user?.fullName ?? 'Owner';
    if (previewBytes != null) {
      return ProfileAvatar(
        name: name,
        bytes: previewBytes,
        size: size,
        showEdit: showEdit,
        onTap: onTap,
        loading: loading,
      );
    }
    final avatar = ref.watch(avatarBytesProvider);
    return avatar.when(
      data: (bytes) => ProfileAvatar(
        name: name,
        bytes: bytes,
        size: size,
        showEdit: showEdit,
        onTap: onTap,
        loading: loading,
      ),
      loading: () => ProfileAvatar(
        name: name,
        size: size,
        showEdit: showEdit,
        onTap: onTap,
        loading: true,
      ),
      error: (_, __) => ProfileAvatar(
        name: name,
        size: size,
        showEdit: showEdit,
        onTap: onTap,
        loading: loading,
      ),
    );
  }
}
