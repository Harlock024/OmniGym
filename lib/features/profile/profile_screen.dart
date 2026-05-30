import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_theme.dart';
import '../../core/models/app_user.dart';
import '../../core/providers/providers.dart';
import 'change_password_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _init(AppUser user) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = user.name;
    _phoneCtrl.text = user.phone ?? '';
  }

  Future<void> _pickAndUploadPhoto(AppUser user) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    if (await file.length() > 2 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La imagen no puede superar 2 MB.')),
        );
      }
      return;
    }

    setState(() => _uploadingPhoto = true);
    try {
      final storageRef =
          FirebaseStorage.instance.ref('profile_photos/${user.id}.jpg');
      await storageRef.putFile(
          file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await storageRef.getDownloadURL();
      await ref
          .read(userRepositoryProvider)
          .updateProfile(user.id, name: user.name, photoUrl: url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto actualizada.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _saveProfile(AppUser user) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).updateProfile(
            user.id,
            name: name,
            phone: _phoneCtrl.text.trim().isEmpty
                ? null
                : _phoneCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentAppUserProvider);

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      appBar: AppBar(
        backgroundColor: OmniGymColors.surface,
        foregroundColor: OmniGymColors.textPrimary,
        elevation: 0,
        title: const Text('Mi perfil'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: OmniGymColors.border),
        ),
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style:
                    const TextStyle(color: OmniGymColors.textSecondary))),
        data: (user) {
          if (user == null) {
            return const Center(
                child: Text('Usuario no encontrado.',
                    style: TextStyle(color: OmniGymColors.textSecondary)));
          }
          _init(user);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AvatarCard(
                      user: user,
                      uploading: _uploadingPhoto,
                      onPickPhoto: () => _pickAndUploadPhoto(user),
                    ),
                    const SizedBox(height: 20),
                    _EditCard(
                      nameCtrl: _nameCtrl,
                      phoneCtrl: _phoneCtrl,
                      saving: _saving,
                      onSave: () => _saveProfile(user),
                    ),
                    const SizedBox(height: 20),
                    _SecurityCard(
                      onChangePassword: () => showDialog(
                        context: context,
                        builder: (_) => const ChangePasswordDialog(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _NotificationsCard(user: user),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Avatar card ──────────────────────────────────────────────────────────────

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.user,
    required this.uploading,
    required this.onPickPhoto,
  });

  final AppUser user;
  final bool uploading;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          GestureDetector(
            onTap: uploading ? null : onPickPhoto,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: OmniGymColors.primary.withAlpha(40),
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: OmniGymColors.primary,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: OmniGymColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: OmniGymColors.card, width: 2),
                    ),
                    child: uploading
                        ? const Padding(
                            padding: EdgeInsets.all(3),
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt,
                            size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    color: OmniGymColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: const TextStyle(
                      color: OmniGymColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                _RoleBadge(role: user.role),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      UserRole.superuser => ('Superusuario', const Color(0xFF7C3AED)),
      UserRole.owner => ('Owner', OmniGymColors.primary),
      UserRole.staff => ('Staff', const Color(0xFF0891B2)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─── Edit card ────────────────────────────────────────────────────────────────

class _EditCard extends StatelessWidget {
  const _EditCard({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Información personal'),
          const SizedBox(height: 16),
          _Field(
            controller: nameCtrl,
            label: 'Nombre completo',
            icon: Icons.person_outline,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: phoneCtrl,
            label: 'Teléfono (opcional)',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Guardar cambios'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Security card ────────────────────────────────────────────────────────────

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.onChangePassword});
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Seguridad'),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: OmniGymColors.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.lock_outline,
                  color: OmniGymColors.primary, size: 18),
            ),
            title: const Text(
              'Cambiar contraseña',
              style: TextStyle(
                  color: OmniGymColors.textPrimary, fontSize: 14),
            ),
            subtitle: const Text(
              'Actualiza tu contraseña de acceso',
              style: TextStyle(
                  color: OmniGymColors.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right,
                color: OmniGymColors.textSecondary),
            onTap: onChangePassword,
          ),
        ],
      ),
    );
  }
}

// ─── Notifications card ───────────────────────────────────────────────────────

class _NotificationsCard extends ConsumerWidget {
  const _NotificationsCard({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = user.notificationPrefs;

    void update(NotificationPrefs updated) =>
        ref.read(userRepositoryProvider).updateNotificationPrefs(user.id, updated);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Notificaciones'),
          const SizedBox(height: 8),
          _PrefTile(
            label: 'Check-ins en mi sucursal',
            value: prefs.checkIns,
            onChanged: (v) => update(prefs.copyWith(checkIns: v)),
          ),
          _PrefTile(
            label: 'Pagos y cobros',
            value: prefs.payments,
            onChanged: (v) => update(prefs.copyWith(payments: v)),
          ),
          _PrefTile(
            label: 'Membresías próximas a vencer',
            value: prefs.memberExpiry,
            onChanged: (v) => update(prefs.copyWith(memberExpiry: v)),
          ),
          _PrefTile(
            label: 'Noticias y promociones',
            value: prefs.marketing,
            onChanged: (v) => update(prefs.copyWith(marketing: v)),
          ),
        ],
      ),
    );
  }
}

class _PrefTile extends StatelessWidget {
  const _PrefTile(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: OmniGymColors.textPrimary, fontSize: 13)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: OmniGymColors.primary,
            trackColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? OmniGymColors.primary.withAlpha(60)
                    : OmniGymColors.border),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets comunes ──────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OmniGymColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OmniGymColors.border),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: OmniGymColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style:
          const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            color: OmniGymColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: OmniGymColors.textSecondary, size: 18),
        filled: true,
        fillColor: OmniGymColors.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: OmniGymColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: OmniGymColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: OmniGymColors.primary)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
