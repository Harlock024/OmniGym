import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_theme.dart';
import '../../core/models/tenant.dart';
import '../../core/providers/providers.dart';
import 'mexico_data.dart';
import 'sat_catalogs.dart';
import 'tenants_screen.dart';

class TenantDetailScreen extends ConsumerStatefulWidget {
  const TenantDetailScreen({super.key, this.tenantId, this.isOwnerMode = false});
  final String? tenantId;
  final bool isOwnerMode;

  @override
  ConsumerState<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _TenantDetailScreenState extends ConsumerState<TenantDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Tenant? _tenant;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // ── Controllers ──────────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final _rfcCtrl = TextEditingController();
  final _razonSocialCtrl = TextEditingController();
  final _giroCtrl = TextEditingController();
  final _serieCtrl = TextEditingController();
  final _numAprobCtrl = TextEditingController();
  final _anioAprobCtrl = TextEditingController();
  final _folioIniCtrl = TextEditingController();
  final _folioFinCtrl = TextEditingController();
  final _folioActCtrl = TextEditingController();

  final _certPassCtrl = TextEditingController();

  String _country = 'MX';
  String? _state;
  String? _municipality;
  String _tipoComprobante = 'I';
  String? _regimenFiscal;
  DateTime? _fechaVencimiento;
  String _primaryColor = '#2563EB';

  // Cert data (session only, never persisted in plain text)
  Uint8List? _cerBytes;
  String? _cerName;
  Uint8List? _keyBytes;
  String? _keyName;

  // Logo
  Uint8List? _logoBytes;
  bool _uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadTenant();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _nameCtrl, _addressCtrl, _postalCtrl, _contactCtrl, _phoneCtrl,
      _emailCtrl, _rfcCtrl, _razonSocialCtrl, _giroCtrl, _serieCtrl,
      _numAprobCtrl, _anioAprobCtrl, _folioIniCtrl, _folioFinCtrl,
      _folioActCtrl, _certPassCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTenant() async {
    final tenantId = widget.tenantId ??
        ref.read(activeTenantIdFutureProvider).valueOrNull ??
        await ref.read(activeTenantIdFutureProvider.future);
    if (tenantId == null) {
      if (mounted) setState(() { _loading = false; _error = 'Tenant no encontrado.'; });
      return;
    }
    final tenant = await ref
        .read(tenantRepositoryProvider)
        .get(tenantId);
    if (!mounted) return;
    if (tenant == null) {
      setState(() { _loading = false; _error = 'Empresa no encontrada.'; });
      return;
    }
    _initFromTenant(tenant);
    setState(() { _tenant = tenant; _loading = false; });
  }

  void _initFromTenant(Tenant t) {
    final s = t.settings;
    _nameCtrl.text = t.name;
    _addressCtrl.text = s.address ?? '';
    _postalCtrl.text = s.postalCode ?? '';
    _contactCtrl.text = s.contactName ?? '';
    _phoneCtrl.text = s.phone ?? '';
    _emailCtrl.text = s.email ?? '';
    _rfcCtrl.text = s.rfc ?? '';
    _razonSocialCtrl.text = s.razonSocial ?? '';
    _giroCtrl.text = s.giro ?? '';
    _serieCtrl.text = s.serie ?? '';
    _numAprobCtrl.text = s.numAprobacion ?? '';
    _anioAprobCtrl.text = s.anioAprobacion ?? '';
    _folioIniCtrl.text = s.folioInicial?.toString() ?? '';
    _folioFinCtrl.text = s.folioFinal?.toString() ?? '';
    _folioActCtrl.text = s.folioActual?.toString() ?? '';
    _state = s.state;
    _municipality = s.municipality;
    _country = s.country;
    _tipoComprobante = s.tipoComprobante;
    _regimenFiscal = s.regimenFiscal;
    _fechaVencimiento = s.fechaVencimiento;
    _primaryColor = s.primaryColor;
    if (s.certCerData != null) {
      _cerBytes = base64Decode(s.certCerData!);
      _cerName = s.certCerName;
    }
    if (s.certKeyData != null) {
      _keyBytes = base64Decode(s.certKeyData!);
      _keyName = s.certKeyName;
    }
  }

  Future<void> _save() async {
    if (_tenant == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      final newSettings = _tenant!.settings.copyWith(
        logoUrl: _tenant!.settings.logoUrl,
        primaryColor: _primaryColor,
        address: _addressCtrl.text.trim().nullIfEmpty,
        postalCode: _postalCtrl.text.trim().nullIfEmpty,
        contactName: _contactCtrl.text.trim().nullIfEmpty,
        phone: _phoneCtrl.text.trim().nullIfEmpty,
        email: _emailCtrl.text.trim().nullIfEmpty,
        state: _state,
        municipality: _municipality,
        country: _country,
        rfc: _rfcCtrl.text.trim().toUpperCase().nullIfEmpty,
        razonSocial: _razonSocialCtrl.text.trim().nullIfEmpty,
        giro: _giroCtrl.text.trim().nullIfEmpty,
        tipoComprobante: _tipoComprobante,
        regimenFiscal: _regimenFiscal,
        serie: _serieCtrl.text.trim().nullIfEmpty,
        numAprobacion: _numAprobCtrl.text.trim().nullIfEmpty,
        anioAprobacion: _anioAprobCtrl.text.trim().nullIfEmpty,
        folioInicial: int.tryParse(_folioIniCtrl.text.trim()),
        folioFinal: int.tryParse(_folioFinCtrl.text.trim()),
        folioActual: int.tryParse(_folioActCtrl.text.trim()),
        fechaVencimiento: _fechaVencimiento,
        certCerData: _cerBytes != null ? base64Encode(_cerBytes!) : null,
        certCerName: _cerName,
        certKeyData: _keyBytes != null ? base64Encode(_keyBytes!) : null,
        certKeyName: _keyName,
      );

      final repo = ref.read(tenantRepositoryProvider);
      await repo.updateName(_tenant!.id, _nameCtrl.text.trim());
      await repo.updateSettings(_tenant!.id, newSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados.')),
        );
        setState(() { _tenant = _tenant!.copyWith(settings: newSettings); });
      }
    } catch (e) {
      setState(() => _error = 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCert(bool isCer) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() {
      if (isCer) {
        _cerBytes = file.bytes;
        _cerName = file.name;
      } else {
        _keyBytes = file.bytes;
        _keyName = file.name;
      }
    });
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 90,
    );
    if (img == null) return;
    final bytes = await img.readAsBytes();
    setState(() => _logoBytes = bytes);

    if (widget.isOwnerMode && _tenant != null) {
      setState(() => _uploadingLogo = true);
      try {
        final ref = FirebaseStorage.instance
            .ref('tenant_logos/${_tenant!.id}/logo.png');
        await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
        final url = await ref.getDownloadURL();
        await this.ref.read(tenantRepositoryProvider).updateSettings(
              _tenant!.id,
              _tenant!.settings.copyWith(logoUrl: url),
            );
        if (mounted) {
          setState(() {
            _tenant = _tenant!.copyWith(
                settings: _tenant!.settings.copyWith(logoUrl: url));
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logo actualizado.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al subir logo: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _uploadingLogo = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: OmniGymColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _tenant == null) {
      return Scaffold(
        backgroundColor: OmniGymColors.background,
        body: Center(child: Text(_error!, style: const TextStyle(color: OmniGymColors.errorRed))),
      );
    }

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          _buildTabs(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildGeneralTab(),
                _buildFiscalTab(),
                _buildCertsTab(),
              ],
            ),
          ),
          if (_error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              color: OmniGymColors.errorRed.withAlpha(20),
              child: Text(_error!, style: const TextStyle(color: OmniGymColors.errorRed, fontSize: 13)),
            ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (widget.isOwnerMode) {
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: OmniGymColors.border, width: 1)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: OmniGymColors.textSecondary, size: 20),
              onPressed: () => context.pop(),
              tooltip: 'Volver',
            ),
            const SizedBox(width: 8),
            const Text(
              'Configuración fiscal',
              style: TextStyle(
                color: OmniGymColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OmniGymColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Breadcrumb
          GestureDetector(
            onTap: () => context.go('/superadmin'),
            child: const Text('Empresas',
                style: TextStyle(color: OmniGymColors.primary, fontSize: 13)),
          ),
          const Text(' / ', style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 13)),
          Text(
            _tenant?.name ?? '',
            style: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: OmniGymColors.textSecondary, size: 18),
            onPressed: () => context.go('/superadmin'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OmniGymColors.border, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            indicatorColor: OmniGymColors.primary,
            labelColor: OmniGymColors.primary,
            unselectedLabelColor: OmniGymColors.textSecondary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(text: 'Datos generales'),
              Tab(text: 'Datos fiscales'),
              Tab(text: 'Datos de certificados'),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Datos generales ────────────────────────────────────────────────

  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + nombre
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LogoUpload(
                bytes: _logoBytes,
                logoUrl: _tenant?.settings.logoUrl,
                name: _tenant?.name ?? '',
                color: _primaryColor,
                onTap: _pickLogo,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _Field(
                  controller: _nameCtrl,
                  label: 'Nombre de la empresa',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Color corporativo
          _SectionLabel('Color corporativo'),
          const SizedBox(height: 8),
          _ColorPicker(
            current: _primaryColor,
            onChanged: (c) => setState(() => _primaryColor = c),
          ),
          const SizedBox(height: 24),
          // Dirección
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _Field(controller: _addressCtrl, label: 'Dirección'),
                    const SizedBox(height: 14),
                    _Dropdown<String>(
                      label: 'Estado',
                      value: _state,
                      items: MexicoData.states
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _state = v;
                        _municipality = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    _Dropdown<String>(
                      label: 'Municipio',
                      value: _municipality,
                      items: MexicoData.getMunicipalities(_state)
                          .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (v) => setState(() => _municipality = v),
                    ),
                    const SizedBox(height: 14),
                    _Field(controller: _postalCtrl, label: 'Código postal'),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _Field(controller: _contactCtrl, label: 'Contacto'),
                    const SizedBox(height: 14),
                    _Field(controller: _phoneCtrl, label: 'Teléfono',
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 14),
                    _Field(controller: _emailCtrl, label: 'Correo electrónico',
                        keyboardType: TextInputType.emailAddress),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Datos fiscales ─────────────────────────────────────────────────

  Widget _buildFiscalTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _Field(controller: _rfcCtrl, label: 'RFC'),
                const SizedBox(height: 14),
                _Field(controller: _razonSocialCtrl, label: 'Razón social'),
                const SizedBox(height: 14),
                _Field(controller: _giroCtrl, label: 'Giro de la empresa'),
                const SizedBox(height: 14),
                _Dropdown<String>(
                  label: 'Comprobante fiscal',
                  value: _tipoComprobante,
                  items: SatCatalogs.tiposComprobante
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _tipoComprobante = v ?? 'I'),
                ),
                const SizedBox(height: 14),
                _Dropdown<String>(
                  label: 'Régimen fiscal',
                  value: _regimenFiscal,
                  items: SatCatalogs.regimenesFiscales
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _regimenFiscal = v),
                ),
                const SizedBox(height: 14),
                _Field(controller: _serieCtrl, label: 'Serie'),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              children: [
                _Field(controller: _numAprobCtrl, label: 'Núm. de aprobación'),
                const SizedBox(height: 14),
                _Field(controller: _anioAprobCtrl, label: 'Año de aprobación',
                    keyboardType: TextInputType.number),
                const SizedBox(height: 14),
                _Field(controller: _folioIniCtrl, label: 'Folio inicial',
                    keyboardType: TextInputType.number),
                const SizedBox(height: 14),
                _Field(controller: _folioFinCtrl, label: 'Folio final',
                    keyboardType: TextInputType.number),
                const SizedBox(height: 14),
                _Field(controller: _folioActCtrl, label: 'Folio actual',
                    keyboardType: TextInputType.number),
                const SizedBox(height: 14),
                _DatePickerField(
                  label: 'Fecha de vencimiento',
                  value: _fechaVencimiento,
                  onChanged: (d) => setState(() => _fechaVencimiento = d),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 3: Datos de certificados ─────────────────────────────────────────

  Widget _buildCertsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel('Certificado SAT (.cer)'),
                const SizedBox(height: 8),
                _CertFileRow(
                  fileName: _cerName,
                  hasData: _cerBytes != null,
                  onPick: () => _pickCert(true),
                  onClear: () => setState(() { _cerBytes = null; _cerName = null; }),
                ),
                const SizedBox(height: 20),
                _SectionLabel('Archivo Key SAT (.key)'),
                const SizedBox(height: 8),
                _CertFileRow(
                  fileName: _keyName,
                  hasData: _keyBytes != null,
                  onPick: () => _pickCert(false),
                  onClear: () => setState(() { _keyBytes = null; _keyName = null; }),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel('Contraseña del certificado'),
                const SizedBox(height: 8),
                _PasswordField(controller: _certPassCtrl),
                const SizedBox(height: 8),
                const Text(
                  'La contraseña solo se usa en operaciones de timbrado y no se almacena.',
                  style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: OmniGymColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => widget.isOwnerMode
                ? context.pop()
                : context.go('/superadmin'),
            style: TextButton.styleFrom(
                foregroundColor: OmniGymColors.textSecondary),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

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
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: OmniGymColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: OmniGymColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: OmniGymColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: OmniGymColors.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      menuMaxHeight: 320,
      dropdownColor: OmniGymColors.card,
      style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: OmniGymColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: OmniGymColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: OmniGymColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: OmniGymColors.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = value != null
        ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
        : '';

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(ctx).colorScheme.copyWith(
                    primary: OmniGymColors.primary,
                    surface: OmniGymColors.card,
                  ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: AbsorbPointer(
        child: TextField(
          controller: TextEditingController(text: text),
          style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
            suffixIcon: const Icon(Icons.calendar_today, color: OmniGymColors.textSecondary, size: 16),
            filled: true,
            fillColor: OmniGymColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: OmniGymColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: OmniGymColors.border),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller});
  final TextEditingController controller;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return _Field(
      controller: widget.controller,
      label: 'Contraseña del certificado',
      obscureText: _obscure,
      suffixIcon: IconButton(
        icon: Icon(
          _obscure ? Icons.visibility_off : Icons.visibility,
          color: OmniGymColors.textSecondary,
          size: 18,
        ),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
  }
}

// ─── Logo uploader ─────────────────────────────────────────────────────────────

class _LogoUpload extends StatelessWidget {
  const _LogoUpload({
    this.bytes,
    this.logoUrl,
    required this.name,
    required this.color,
    required this.onTap,
  });

  final Uint8List? bytes;
  final String? logoUrl;
  final String name;
  final String color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              bytes != null
                  ? CircleAvatar(
                      radius: 36,
                      backgroundImage: MemoryImage(bytes!),
                    )
                  : TenantAvatar(
                      logoUrl: logoUrl,
                      name: name,
                      color: color,
                      radius: 36,
                    ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: OmniGymColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: OmniGymColors.background, width: 2),
                  ),
                  child: const Icon(Icons.edit, size: 12, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Cambiar logo',
          style: const TextStyle(color: OmniGymColors.primary, fontSize: 11),
        ),
      ],
    );
  }
}

// ─── Cert file row ─────────────────────────────────────────────────────────────

class _CertFileRow extends StatelessWidget {
  const _CertFileRow({
    this.fileName,
    required this.hasData,
    required this.onPick,
    required this.onClear,
  });

  final String? fileName;
  final bool hasData;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (hasData && fileName != null) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: OmniGymColors.success, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName!,
              style: const TextStyle(color: OmniGymColors.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.swap_horiz, size: 14),
            label: const Text('Reemplazar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: OmniGymColors.textSecondary,
              side: const BorderSide(color: OmniGymColors.border),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline, color: OmniGymColors.errorRed, size: 18),
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: onPick,
      icon: const Icon(Icons.upload_file, size: 16),
      label: const Text('Seleccionar archivo'),
      style: OutlinedButton.styleFrom(
        foregroundColor: OmniGymColors.textSecondary,
        side: const BorderSide(color: OmniGymColors.border),
      ),
    );
  }
}

// ─── Color picker ─────────────────────────────────────────────────────────────

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  static const _presets = [
    '#2563EB', // azul (default)
    '#7C3AED', // morado
    '#0891B2', // cyan
    '#16A34A', // verde
    '#DC2626', // rojo
    '#EA580C', // naranja
    '#0D9488', // teal
    '#DB2777', // rosa
    '#475569', // gris oscuro
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presets.map((hex) {
        final color = _hexToColor(hex);
        final isSelected = current.toLowerCase() == hex.toLowerCase();
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withAlpha(120), blurRadius: 6)]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _hexToColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return OmniGymColors.primary;
    }
  }
}

extension _StringX on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
