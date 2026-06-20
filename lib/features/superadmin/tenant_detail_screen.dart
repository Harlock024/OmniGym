import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_theme.dart';
import '../../core/models/tenant.dart';
import '../../core/models/tenant_invoice.dart';
import '../../core/providers/providers.dart';
import '../../core/services/r2_storage_service.dart';
import '../../core/services/theme_service.dart';
import '../../core/services/worker_service.dart';
import '../../core/utils/rfc_validator.dart';
import 'mexico_data.dart';
import 'sat_catalogs.dart';
import 'superadmin_providers.dart';
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
  final _coloniaCtrl = TextEditingController();
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
  String _metodoPago = 'PUE';
  String _formaPago = '01';
  String _usoCFDI = 'G03';
  DateTime? _fechaVencimiento;
  String _primaryColor = '#2563EB';
  String _secondaryColor = '#03DAC6';
  String _themeMode = 'system';

  String? _rfcError;

  // Autocompletado postal (catálogo SEPOMEX vía worker/D1).
  List<String> _colonias = [];
  String? _cpEstado;
  String? _cpMunicipio;
  String? _cpCiudad;
  bool _cpLoading = false;

  // Cert data (los bytes se suben a R2 al guardar; solo persistimos la URL).
  Uint8List? _cerBytes;
  String? _cerName;
  String? _cerUrl;
  bool _cerDirty = false;
  Uint8List? _keyBytes;
  String? _keyName;
  String? _keyUrl;
  bool _keyDirty = false;

  // Logo
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    // En modo SuperAdmin se añade la pestaña de cobro (facturación SaaS B2B).
    _tabs = TabController(length: widget.isOwnerMode ? 3 : 4, vsync: this);
    _loadTenant();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _nameCtrl, _addressCtrl, _coloniaCtrl, _postalCtrl, _contactCtrl, _phoneCtrl,
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
    if (RegExp(r'^\d{5}$').hasMatch(_postalCtrl.text)) {
      _lookupCp(_postalCtrl.text);
    }
  }

  // Consulta el catálogo postal y precarga estado/municipio/colonias.
  Future<void> _lookupCp(String cp) async {
    if (!RegExp(r'^\d{5}$').hasMatch(cp)) {
      setState(() {
        _colonias = [];
        _cpEstado = null;
        _cpMunicipio = null;
        _cpCiudad = null;
      });
      return;
    }
    setState(() => _cpLoading = true);
    final r = await WorkerService.lookupPostalCode(cp);
    if (!mounted) return;
    setState(() {
      _cpLoading = false;
      if (r != null) {
        _cpEstado = r.estado;
        _cpMunicipio = r.municipio;
        _cpCiudad = r.ciudad;
        _colonias = r.colonias;
        // Sincroniza los dropdowns de estado/municipio desde SEPOMEX
        // para facturación precisa (CFDI requiere dirección fiscal real).
        if (r.estado != null) _state = r.estado;
        _municipality = r.municipio;
      } else {
        _cpEstado = null;
        _cpMunicipio = null;
        _cpCiudad = null;
        _colonias = [];
      }
    });
  }

  void _initFromTenant(Tenant t) {
    final s = t.settings;
    _nameCtrl.text = t.name;
    _addressCtrl.text = s.address ?? '';
    _coloniaCtrl.text = s.colonia ?? '';
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
    _metodoPago = s.metodoPago;
    _formaPago = s.formaPago;
    _usoCFDI = s.usoCFDI;
    _fechaVencimiento = s.fechaVencimiento;
    _primaryColor = s.primaryColor;
    _secondaryColor = s.secondaryColor;
    _themeMode = s.themeMode;
    _cerName = s.certCerName;
    _keyName = s.certKeyName;
    _cerUrl = s.certCerUrl;
    _keyUrl = s.certKeyUrl;
    // Compatibilidad con tenants previos a la migración a R2 (base64 en Firestore).
    if (s.certCerUrl == null && s.certCerData != null) {
      _cerBytes = base64Decode(s.certCerData!);
    }
    if (s.certKeyUrl == null && s.certKeyData != null) {
      _keyBytes = base64Decode(s.certKeyData!);
    }
  }

  Future<void> _save() async {
    if (_tenant == null) return;

    // Validación de RFC (formato + dígito verificador) antes de persistir.
    final rfcError = RfcValidator.validate(_rfcCtrl.text);
    if (rfcError != null) {
      setState(() { _rfcError = rfcError; _error = rfcError; });
      _tabs.animateTo(1);
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      // Subir certificados nuevos a Cloudflare R2; solo persistimos la URL.
      var cerUrl = _cerUrl;
      var keyUrl = _keyUrl;
      if (_cerDirty && _cerBytes != null) {
        cerUrl = await R2StorageService.upload(
          bytes: _cerBytes!,
          key: 'tenant_csd/${_tenant!.id}/certificate.cer',
          contentType: 'application/octet-stream',
        );
      }
      if (_keyDirty && _keyBytes != null) {
        keyUrl = await R2StorageService.upload(
          bytes: _keyBytes!,
          key: 'tenant_csd/${_tenant!.id}/certificate.key',
          contentType: 'application/octet-stream',
        );
      }

      final newSettings = _tenant!.settings.copyWith(
        logoUrl: _tenant!.settings.logoUrl,
        primaryColor: _primaryColor,
        secondaryColor: _secondaryColor,
        themeMode: _themeMode,
        address: _addressCtrl.text.trim().nullIfEmpty,
        colonia: _coloniaCtrl.text.trim().nullIfEmpty,
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
        metodoPago: _metodoPago,
        formaPago: _formaPago,
        usoCFDI: _usoCFDI,
        serie: _serieCtrl.text.trim().nullIfEmpty,
        numAprobacion: _numAprobCtrl.text.trim().nullIfEmpty,
        anioAprobacion: _anioAprobCtrl.text.trim().nullIfEmpty,
        folioInicial: int.tryParse(_folioIniCtrl.text.trim()),
        folioFinal: int.tryParse(_folioFinCtrl.text.trim()),
        folioActual: int.tryParse(_folioActCtrl.text.trim()),
        fechaVencimiento: _fechaVencimiento,
        certCerUrl: cerUrl,
        certKeyUrl: keyUrl,
        certCerName: _cerName,
        certKeyName: _keyName,
        csdUploaded: cerUrl != null && keyUrl != null,
        // Migra fuera del esquema legacy: ya no guardamos los archivos en Firestore.
        certCerData: null,
        certKeyData: null,
      );

      final repo = ref.read(tenantRepositoryProvider);
      await repo.updateName(_tenant!.id, _nameCtrl.text.trim());
      await repo.updateSettings(_tenant!.id, newSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados.')),
        );
        setState(() {
          _tenant = _tenant!.copyWith(settings: newSettings);
          _cerUrl = newSettings.certCerUrl;
          _keyUrl = newSettings.certKeyUrl;
          _cerDirty = false;
          _keyDirty = false;
        });
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
        _cerDirty = true;
      } else {
        _keyBytes = file.bytes;
        _keyName = file.name;
        _keyDirty = true;
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
      try {
        final url = await R2StorageService.upload(
          bytes: bytes,
          key: 'tenant_logos/${_tenant!.id}/logo.png',
          contentType: 'image/png',
        );
        await ref.read(tenantRepositoryProvider).updateSettings(
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _tenant == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                if (!widget.isOwnerMode) _buildBillingTab(),
              ],
            ),
          ),
          if (_error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              color: Theme.of(context).colorScheme.error.withAlpha(20),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (widget.isOwnerMode) {
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        color: cs.primary,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: cs.onPrimary, size: 20),
              onPressed: () => context.go('/dashboard/owner'),
              tooltip: 'Volver',
            ),
            const SizedBox(width: 8),
            Text(
              'Configuración fiscal',
              style: TextStyle(
                color: cs.onPrimary,
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
      color: cs.primary,
      child: Row(
        children: [
          // Breadcrumb
          GestureDetector(
            onTap: () => context.go('/superadmin'),
            child: Text('Empresas',
                style: TextStyle(color: cs.onPrimary, fontSize: 13)),
          ),
          Text(' / ', style: TextStyle(color: cs.onPrimary.withAlpha(180), fontSize: 13)),
          Text(
            _tenant?.name ?? '',
            style: TextStyle(color: cs.onPrimary.withAlpha(180), fontSize: 13),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, color: cs.onPrimary, size: 18),
            onPressed: () => context.go('/superadmin'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: theme.dividerTheme.color ?? OmniGymColors.border, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            indicatorColor: cs.primary,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: [
              const Tab(text: 'Datos generales'),
              const Tab(text: 'Datos fiscales'),
              const Tab(text: 'Datos de certificados'),
              if (!widget.isOwnerMode) const Tab(text: 'Cobro'),
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
          // Apariencia del Gym
          _SectionLabel('Apariencia del Gym'),
          const SizedBox(height: 16),
          _SectionLabel('Color primario'),
          const SizedBox(height: 8),
          _ColorGrid(
            colors: OmniGymPalette.primaries,
            current: _primaryColor,
            onChanged: (c) => setState(() => _primaryColor = c),
          ),
          const SizedBox(height: 16),
          _SectionLabel('Color secundario'),
          const SizedBox(height: 8),
          _ColorGrid(
            colors: OmniGymPalette.secondaries,
            current: _secondaryColor,
            onChanged: (c) => setState(() => _secondaryColor = c),
          ),
          const SizedBox(height: 16),
          _SectionLabel('Modo'),
          const SizedBox(height: 8),
          _ThemeModeSelector(
            value: _themeMode,
            onChanged: (v) => setState(() => _themeMode = v),
          ),
          const SizedBox(height: 16),
          _SectionLabel('Vista previa'),
          const SizedBox(height: 8),
          _ThemePreview(
            primary: _primaryColor,
            secondary: _secondaryColor,
            themeMode: _themeMode,
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
                    _buildPostalField(),
                    const SizedBox(height: 14),
                    _buildColoniaField(),
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

  // Campo de CP con autocompletado postal + confirmación estado/municipio.
  Widget _buildPostalField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Field(
          controller: _postalCtrl,
          label: 'Código postal',
          keyboardType: TextInputType.number,
          onChanged: (v) => _lookupCp(v.trim()),
          suffixIcon: _cpLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        if (_cpEstado != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              [_cpMunicipio, _cpEstado, _cpCiudad]
                  .where((e) => e != null && e.isNotEmpty)
                  .join(' · '),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
            ),
          ),
      ],
    );
  }

  // Colonia: dropdown desde el catálogo cuando hay resultados; texto libre si no.
  Widget _buildColoniaField() {
    if (_colonias.isEmpty) {
      return _Field(controller: _coloniaCtrl, label: 'Colonia');
    }
    final current = _coloniaCtrl.text.trim();
    final options = <String>{
      ..._colonias,
      if (current.isNotEmpty) current,
    }.toList();
    return _Dropdown<String>(
      label: 'Colonia',
      value: current.isEmpty ? null : current,
      items: options
          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
          .toList(),
      onChanged: (v) => setState(() => _coloniaCtrl.text = v ?? ''),
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
                _Field(
                  controller: _rfcCtrl,
                  label: 'RFC',
                  textCapitalization: TextCapitalization.characters,
                  errorText: _rfcError,
                  onChanged: (v) =>
                      setState(() => _rfcError = RfcValidator.validate(v)),
                ),
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
                _Dropdown<String>(
                  label: 'Método de pago',
                  value: _metodoPago,
                  items: SatCatalogs.metodosPago
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _metodoPago = v ?? 'PUE'),
                ),
                const SizedBox(height: 14),
                _Dropdown<String>(
                  label: 'Forma de pago',
                  value: _formaPago,
                  items: SatCatalogs.formasPago
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _formaPago = v ?? '01'),
                ),
                const SizedBox(height: 14),
                _Dropdown<String>(
                  label: 'Uso CFDI',
                  value: _usoCFDI,
                  items: SatCatalogs.usosCFDI
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _usoCFDI = v ?? 'G03'),
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
                  hasData: _cerBytes != null || _cerUrl != null,
                  onPick: () => _pickCert(true),
                  onClear: () => setState(() {
                    _cerBytes = null;
                    _cerName = null;
                    _cerUrl = null;
                    _cerDirty = true;
                  }),
                ),
                const SizedBox(height: 20),
                _SectionLabel('Archivo Key SAT (.key)'),
                const SizedBox(height: 8),
                _CertFileRow(
                  fileName: _keyName,
                  hasData: _keyBytes != null || _keyUrl != null,
                  onPick: () => _pickCert(false),
                  onClear: () => setState(() {
                    _keyBytes = null;
                    _keyName = null;
                    _keyUrl = null;
                    _keyDirty = true;
                  }),
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
                Text(
                  'La contraseña solo se usa en operaciones de timbrado y no se almacena.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 4: Cobro (facturación SaaS B2B, solo SuperAdmin) ──────────────────

  /// Suspende o reactiva manualmente el acceso del gimnasio (kill switch del
  /// SuperAdmin). Es independiente de `past_due`, que gobierna Stripe.
  Future<void> _setSubscriptionStatus(SubscriptionStatus status) async {
    final id = widget.tenantId;
    if (id == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(tenantRepositoryProvider)
          .updateSubscriptionStatus(id, status);
      if (mounted) {
        setState(() =>
            _tenant = _tenant?.copyWith(subscriptionStatus: status));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo actualizar el estado: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildBillingTab() {
    final tenant = _tenant;
    if (tenant == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final status = tenant.subscriptionStatus;
    final pastDue =
        tenant.pastDue && status == SubscriptionStatus.active;
    final d = tenant.billingCycleEnd;
    final fecha =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final (statusLabel, statusColor) = pastDue
        ? ('Pago vencido', Theme.of(context).colorScheme.error)
        : switch (status) {
            SubscriptionStatus.active => ('Activo', OmniGymColors.success),
            SubscriptionStatus.suspended => ('Suspendido', Colors.orange),
            SubscriptionStatus.cancelled =>
              ('Cancelado', Theme.of(context).colorScheme.error),
          };

    final isActive = status == SubscriptionStatus.active;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const _SectionLabel('Estado de la suscripción'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withAlpha(80)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withAlpha(80)),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  Text('Próximo cobro: $fecha',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              _kv('Cliente Stripe', tenant.stripeCustomerId ?? '—'),
              _kv('Plan (price ID)', tenant.packagePriceId ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionLabel('Kill switch manual'),
        const SizedBox(height: 8),
        Text(
          isActive
              ? 'Suspende el acceso del gimnasio de inmediato. Úsalo solo como medida administrativa; el estado de pago lo gestiona Stripe automáticamente.'
              : 'Reactiva el acceso del gimnasio. Si tiene un pago pendiente con Stripe, seguirá bloqueado hasta que regularice.',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: isActive
              ? OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _setSubscriptionStatus(
                          SubscriptionStatus.suspended),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(color: Theme.of(context).colorScheme.error)),
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Suspender acceso'),
                )
              : FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _setSubscriptionStatus(
                          SubscriptionStatus.active),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Reactivar acceso'),
                ),
        ),
        const SizedBox(height: 24),
        const _SectionLabel('Historial de facturas'),
        const SizedBox(height: 12),
        Consumer(
          builder: (context, ref, _) {
            final invoicesAsync =
                ref.watch(tenantInvoicesProvider(widget.tenantId!));
            return invoicesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('No se pudo cargar el historial: $e',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              data: (invoices) => invoices.isEmpty
                  ? Text('Aún no hay facturas registradas.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))
                  : Column(
                      children: invoices
                          .map((inv) => _InvoiceTile(invoice: inv))
                          .toList(),
                    ),
            );
          },
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => context.go(
                widget.isOwnerMode ? '/dashboard/owner' : '/superadmin'),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
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
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    this.errorText,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        errorText: errorText,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
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
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      menuMaxHeight: 320,
      dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
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
                    primary: Theme.of(context).colorScheme.primary,
                    surface: Theme.of(context).colorScheme.surfaceContainerHighest,
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            suffixIcon: Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 16),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
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
          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                  ),
                  child: Icon(Icons.edit, size: 12, color: Theme.of(context).colorScheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Cambiar logo',
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11),
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
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.swap_horiz, size: 14),
            label: const Text('Reemplazar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              side: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onClear,
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 18),
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: onPick,
      icon: const Icon(Icons.upload_file, size: 16),
      label: const Text('Seleccionar archivo'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        side: BorderSide(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
      ),
    );
  }
}

// ─── Color grid ───────────────────────────────────────────────────────────────

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({
    required this.colors,
    required this.current,
    required this.onChanged,
  });

  final List<Color> colors;
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: colors.map((color) {
        final hex = color.toHex();
        final isSelected = current.toLowerCase() == hex.toLowerCase();
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: theme.colorScheme.onSurface,
                      width: 3,
                    )
                  : Border.all(
                      color: theme.dividerTheme.color ?? Colors.transparent,
                      width: 1,
                    ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withAlpha(120), blurRadius: 6)]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Theme mode selector ──────────────────────────────────────────────────────

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'light', label: Text('Claro')),
        ButtonSegment(value: 'dark', label: Text('Oscuro')),
        ButtonSegment(value: 'system', label: Text('Sistema')),
      ],
      selected: {value},
      onSelectionChanged: (selected) => onChanged(selected.first),
    );
  }
}

// ─── Theme preview ────────────────────────────────────────────────────────────

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.primary,
    required this.secondary,
    required this.themeMode,
  });

  final String primary;
  final String secondary;
  final String themeMode;

  @override
  Widget build(BuildContext context) {
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (themeMode) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => platformBrightness,
    };
    final theme = ThemeService.buildTheme(
      tenant: Tenant(
        id: 'preview',
        slug: 'preview',
        name: 'Vista previa',
        subscriptionStatus: SubscriptionStatus.active,
        billingCycleEnd: DateTime.now().add(const Duration(days: 30)),
        settings: TenantSettings(
          primaryColor: primary,
          secondaryColor: secondary,
          themeMode: themeMode,
        ),
      ),
      brightness: brightness,
    );

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppBar(
                  title: const Text('Vista previa'),
                  centerTitle: false,
                  automaticallyImplyLeading: false,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ejemplo de tarjeta',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Así se verá la app con esta combinación de colores.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              FilledButton(
                                onPressed: () {},
                                child: const Text('Primario'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed: () {},
                                child: const Text('Secundario'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

extension _StringX on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice});
  final TenantInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (invoice.status) {
      'paid' => ('Pagada', OmniGymColors.success),
      'open' => ('Pendiente', Colors.orange),
      'void' => ('Anulada', Theme.of(context).colorScheme.onSurfaceVariant),
      'uncollectible' => ('Incobrable', Theme.of(context).colorScheme.error),
      _ => (invoice.status, Theme.of(context).colorScheme.onSurfaceVariant),
    };
    final d = invoice.createdAt;
    final fecha = d == null
        ? '—'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? OmniGymColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fecha,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(invoice.id,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          Text(
            '\$${invoice.amount.toStringAsFixed(2)} ${invoice.currency.toUpperCase()}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
