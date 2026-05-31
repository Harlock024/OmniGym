import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../core/models/branch.dart';
import '../../core/models/member.dart';
import '../../core/providers/providers.dart';

// ─── Estado del kiosko ────────────────────────────────────────────────────────

enum _KioskState { idle, loading, success, error }

class _KioskResult {
  const _KioskResult({this.member, this.errorMsg});
  final Member? member;
  final String? errorMsg;
  bool get isSuccess => member != null;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends ConsumerState<KioskScreen>
    with SingleTickerProviderStateMixin {
  final _codeCtrl = TextEditingController();
  final _focusNode = FocusNode();

  _KioskState _state = _KioskState.idle;
  _KioskResult? _result;
  Timer? _resetTimer;
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;

  // Branch seleccionada para el kiosko
  String? _tenantId;
  Branch? _selectedBranch;
  List<Branch> _branches = [];
  bool _loadingBranches = true;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut);
    _loadSetup();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focusNode.dispose();
    _resetTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSetup() async {
    final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
        ?? await ref.read(activeTenantIdFutureProvider.future);
    if (!mounted || tenantId == null) return;

    final branches = await ref.read(branchRepositoryProvider).watchAll(tenantId).first;
    if (!mounted) return;
    setState(() {
      _tenantId = tenantId;
      _branches = branches;
      _loadingBranches = false;
      if (branches.length == 1) {
        _selectedBranch = branches.first;
        _focusTextField();
      }
    });
  }

  void _focusTextField() {
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusNode.requestFocus());
  }

  Future<void> _processCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || _state == _KioskState.loading) return;
    _codeCtrl.clear();

    if (_tenantId == null || _selectedBranch == null) return;

    setState(() => _state = _KioskState.loading);

    try {
      final member = await ref
          .read(memberRepositoryProvider)
          .getByQrToken(_tenantId!, trimmed);

      if (member == null) {
        return _setError('Socio no encontrado');
      }
      if (member.accessStatus == AccessStatus.suspended) {
        return _setError('Acceso suspendido');
      }
      if (member.expirationDate.isBefore(DateTime.now())) {
        return _setError('Membresía vencida');
      }
      if (!member.allowedBranches.contains(_selectedBranch!.id)) {
        return _setError('Sucursal no habilitada');
      }

      // Registrar check-in
      await ref.read(memberRepositoryProvider).logCheckIn(
        tenantId: _tenantId!,
        branchId: _selectedBranch!.id,
        checkInData: {
          'member_id': member.id,
          'member_name': member.name,
          'qr_token': trimmed,
          'tenant_id': _tenantId!,
          'branch_id': _selectedBranch!.id,
          'expiration_date': Timestamp.fromDate(member.expirationDate),
          'plan_id': member.planId,
        },
      );

      setState(() {
        _state = _KioskState.success;
        _result = _KioskResult(member: member);
      });
      _animCtrl.forward(from: 0);
      HapticFeedback.lightImpact();
      _scheduleReset();
    } catch (e) {
      _setError('Error al procesar');
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _state = _KioskState.error;
      _result = _KioskResult(errorMsg: msg);
    });
    _animCtrl.forward(from: 0);
    HapticFeedback.heavyImpact();
    _scheduleReset();
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _state = _KioskState.idle;
        _result = null;
      });
      _animCtrl.reset();
      _focusTextField();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: _loadingBranches
          ? const Center(child: CircularProgressIndicator())
          : _selectedBranch == null
              ? _BranchSelector(
                  branches: _branches,
                  onSelect: (b) => setState(() {
                    _selectedBranch = b;
                    _focusTextField();
                  }),
                )
              : _KioskBody(
                  branch: _selectedBranch!,
                  state: _state,
                  result: _result,
                  scaleAnim: _scaleAnim,
                  codeCtrl: _codeCtrl,
                  focusNode: _focusNode,
                  onCode: _processCode,
                  onChangeBranch: () => setState(() {
                    _selectedBranch = null;
                    _state = _KioskState.idle;
                    _result = null;
                  }),
                ),
    );
  }
}

// ─── Selector de sucursal ─────────────────────────────────────────────────────

class _BranchSelector extends StatelessWidget {
  const _BranchSelector({required this.branches, required this.onSelect});
  final List<Branch> branches;
  final ValueChanged<Branch> onSelect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: OmniGymColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.fitness_center,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(height: 24),
            const Text(
              'Selecciona la sucursal',
              style: TextStyle(
                color: OmniGymColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Este dispositivo funcionará como kiosko de acceso',
              style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ...branches.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => onSelect(b),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(b.name,
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Cuerpo del kiosko ────────────────────────────────────────────────────────

class _KioskBody extends StatelessWidget {
  const _KioskBody({
    required this.branch,
    required this.state,
    required this.result,
    required this.scaleAnim,
    required this.codeCtrl,
    required this.focusNode,
    required this.onCode,
    required this.onChangeBranch,
  });

  final Branch branch;
  final _KioskState state;
  final _KioskResult? result;
  final Animation<double> scaleAnim;
  final TextEditingController codeCtrl;
  final FocusNode focusNode;
  final ValueChanged<String> onCode;
  final VoidCallback onChangeBranch;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Fondo de color según estado ──────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          color: switch (state) {
            _KioskState.success => const Color(0xFF0A2A1A),
            _KioskState.error   => const Color(0xFF2A0A0A),
            _                   => OmniGymColors.background,
          },
        ),

        // ── Contenido central ────────────────────────────────────────────
        Center(
          child: switch (state) {
            _KioskState.idle || _KioskState.loading => _IdleView(
                branch: branch,
                isLoading: state == _KioskState.loading,
                codeCtrl: codeCtrl,
                focusNode: focusNode,
                onCode: onCode,
              ),
            _KioskState.success => ScaleTransition(
                scale: scaleAnim,
                child: _SuccessView(member: result!.member!),
              ),
            _KioskState.error => ScaleTransition(
                scale: scaleAnim,
                child: _ErrorView(message: result!.errorMsg!),
              ),
          },
        ),

        // ── Botón cambiar sucursal ────────────────────────────────────────
        Positioned(
          top: 16,
          right: 16,
          child: TextButton.icon(
            onPressed: onChangeBranch,
            icon: const Icon(Icons.swap_horiz,
                size: 16, color: OmniGymColors.textSecondary),
            label: Text(
              branch.name,
              style: const TextStyle(
                  color: OmniGymColors.textSecondary, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Vista en espera ───────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.branch,
    required this.isLoading,
    required this.codeCtrl,
    required this.focusNode,
    required this.onCode,
  });

  final Branch branch;
  final bool isLoading;
  final TextEditingController codeCtrl;
  final FocusNode focusNode;
  final ValueChanged<String> onCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: OmniGymColors.primary.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: OmniGymColors.primary),
                )
              : const Icon(Icons.qr_code_scanner_rounded,
                  color: OmniGymColors.primary, size: 40),
        ),
        const SizedBox(height: 28),
        const Text(
          'Escanea tu código QR',
          style: TextStyle(
            color: OmniGymColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Acerca tu código al lector',
          style: TextStyle(
              color: OmniGymColors.textSecondary, fontSize: 16),
        ),
        // Campo invisible para recibir el input del lector
        SizedBox(
          width: 0,
          height: 0,
          child: TextField(
            controller: codeCtrl,
            focusNode: focusNode,
            autofocus: true,
            onSubmitted: onCode,
            style: const TextStyle(fontSize: 0, color: Colors.transparent),
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
      ],
    );
  }
}

// ── Vista de éxito ────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: OmniGymColors.success.withAlpha(30),
            shape: BoxShape.circle,
            border: Border.all(color: OmniGymColors.success, width: 3),
          ),
          child: const Icon(Icons.check_rounded,
              color: OmniGymColors.success, size: 60),
        ),
        const SizedBox(height: 28),
        Text(
          member.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: OmniGymColors.success.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OmniGymColors.success.withAlpha(80)),
          ),
          child: const Text(
            '¡Bienvenido!',
            style: TextStyle(
              color: OmniGymColors.success,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Vista de error ────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: OmniGymColors.errorRed.withAlpha(30),
            shape: BoxShape.circle,
            border: Border.all(color: OmniGymColors.errorRed, width: 3),
          ),
          child: const Icon(Icons.close_rounded,
              color: OmniGymColors.errorRed, size: 60),
        ),
        const SizedBox(height: 28),
        Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Contacta a recepción',
          style: TextStyle(
              color: OmniGymColors.textSecondary, fontSize: 16),
        ),
      ],
    );
  }
}
