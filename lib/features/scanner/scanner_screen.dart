import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/app_shell.dart';
import '../../app/app_theme.dart';
import '../../core/models/member.dart';
import '../../core/providers/providers.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _scanResultProvider = StateProvider<_ScanResult?>((ref) => null);
final _scanLoadingProvider = StateProvider<bool>((ref) => false);

// Sucursal elegida por el owner para registrar accesos (null = sin elegir).
final _selectedScanBranchProvider = StateProvider<String?>((ref) => null);

// Sucursal efectiva del escáner:
//  • staff → su propia sucursal (claim, con fallback a Firestore)
//  • owner/superuser → la que selecciona en el encabezado
final _scanBranchIdProvider = FutureProvider<String?>((ref) async {
  final role = await ref.watch(currentUserRoleProvider.future);
  if (role == 'owner' || role == 'superuser') {
    return ref.watch(_selectedScanBranchProvider);
  }
  return ref.watch(currentBranchIdProvider.future);
});

class _ScanResult {
  const _ScanResult({this.member, this.error});
  final Member? member;
  final String? error;

  bool get isSuccess => member != null;
}

final _recentCheckInsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final tenantId = await ref.watch(activeTenantIdFutureProvider.future);
  final branchId = await ref.watch(_scanBranchIdProvider.future);
  if (tenantId == null || branchId == null) { yield []; return; }

  final db = ref.watch(firestoreProvider);
  final today = DateTime.now();
  final midnight = DateTime(today.year, today.month, today.day);

  yield* db
      .collection('tenants')
      .doc(tenantId)
      .collection('branches')
      .doc(branchId)
      .collection('check_ins')
      .where('timestamp', isGreaterThanOrEqualTo: midnight)
      .orderBy('timestamp', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {...d.data(), 'id': d.id}).toList());
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class ScannerScreen extends ConsumerWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isMobile) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: OmniGymColors.background,
          appBar: AppBar(
            backgroundColor: OmniGymColors.surface,
            leading: const DrawerMenuButton(),
            automaticallyImplyLeading: false,
            title: const Text('Control de Acceso'),
            bottom: const TabBar(
              indicatorColor: OmniGymColors.primary,
              labelColor: OmniGymColors.primary,
              unselectedLabelColor: OmniGymColors.textSecondary,
              tabs: [
                Tab(text: 'Escáner'),
                Tab(text: 'Accesos hoy'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _ScanPanel(),
              const _CheckInsPanel(),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: OmniGymColors.background,
      body: Row(
        children: [
          Expanded(flex: 5, child: _ScanPanel()),
          const VerticalDivider(color: OmniGymColors.border, width: 1),
          const Expanded(flex: 4, child: _CheckInsPanel()),
        ],
      ),
    );
  }
}

// ─── Panel de escaneo ─────────────────────────────────────────────────────────

class _ScanPanel extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ScanPanel> createState() => _ScanPanelState();
}

class _ScanPanelState extends ConsumerState<_ScanPanel> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  MobileScannerController? _cameraCtrl;
  bool _showManualEntry = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.isMobile) {
        setState(() {
          _cameraCtrl = MobileScannerController(
            detectionSpeed: DetectionSpeed.noDuplicates,
          );
        });
      } else {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _cameraCtrl?.dispose();
    super.dispose();
  }

  Future<void> _processCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    _ctrl.clear();

    ref.read(_scanLoadingProvider.notifier).state = true;
    ref.read(_scanResultProvider.notifier).state = null;

    try {
      final tenantId = ref.read(activeTenantIdFutureProvider).valueOrNull
          ?? await ref.read(activeTenantIdFutureProvider.future);
      final branchId = await ref.read(_scanBranchIdProvider.future);

      if (tenantId == null || branchId == null) {
        final role = await ref.read(currentUserRoleProvider.future);
        ref.read(_scanResultProvider.notifier).state = _ScanResult(
          error: (role == 'owner' || role == 'superuser')
              ? 'Selecciona una sucursal para registrar el acceso.'
              : 'Sin sucursal asignada.',
        );
        return;
      }

      final member = await ref
          .read(memberRepositoryProvider)
          .getByQrToken(tenantId, trimmed);

      if (member == null) {
        ref.read(_scanResultProvider.notifier).state =
            const _ScanResult(error: 'Socio no encontrado.');
        return;
      }

      if (member.accessStatus == AccessStatus.suspended) {
        ref.read(_scanResultProvider.notifier).state =
            const _ScanResult(error: 'Acceso suspendido.');
        return;
      }

      if (member.expirationDate.isBefore(DateTime.now())) {
        ref.read(_scanResultProvider.notifier).state =
            const _ScanResult(error: 'Membresía vencida.');
        return;
      }

      if (!member.allowedBranches.contains(branchId)) {
        ref.read(_scanResultProvider.notifier).state =
            const _ScanResult(error: 'Esta sucursal no está habilitada para este socio.');
        return;
      }

      await ref.read(memberRepositoryProvider).logCheckIn(
        tenantId: tenantId,
        branchId: branchId,
        checkInData: {
          'member_id': member.id,
          'member_name': member.name,
          'qr_token': trimmed,
          'tenant_id': tenantId,
          'branch_id': branchId,
          'expiration_date': Timestamp.fromDate(member.expirationDate),
          'plan_id': member.planId,
        },
      );

      ref.read(_scanResultProvider.notifier).state = _ScanResult(member: member);
    } catch (e) {
      ref.read(_scanResultProvider.notifier).state =
          _ScanResult(error: 'Error inesperado: $e');
    } finally {
      ref.read(_scanLoadingProvider.notifier).state = false;
      if (_cameraCtrl == null) _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(_scanResultProvider);
    final loading = ref.watch(_scanLoadingProvider);
    final isMobile = context.isMobile;

    // ── Mobile: camera scanner ───────────────────────────────────────────────
    if (isMobile) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _OwnerBranchSelector(),
            // Camera preview
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 1,
                child: _cameraCtrl != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: _cameraCtrl!,
                            onDetect: (capture) {
                              if (loading) return;
                              final code = capture.barcodes.firstOrNull?.rawValue;
                              if (code != null && code.isNotEmpty) {
                                _processCode(code);
                              }
                            },
                            overlayBuilder: (_, constraints) => CustomPaint(
                              size: constraints.biggest,
                              painter: _CornersPainter(),
                            ),
                          ),
                          if (loading)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white),
                              ),
                            ),
                        ],
                      )
                    : const ColoredBox(
                        color: OmniGymColors.surface,
                        child: Center(child: CircularProgressIndicator()),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Apunta al código QR del socio',
              style: TextStyle(
                  color: OmniGymColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _showManualEntry = !_showManualEntry),
                icon: Icon(
                  _showManualEntry
                      ? Icons.keyboard_hide_outlined
                      : Icons.keyboard_outlined,
                  size: 16,
                ),
                label: Text(_showManualEntry
                    ? 'Ocultar teclado'
                    : 'Ingresar código manual'),
                style: TextButton.styleFrom(
                  foregroundColor: OmniGymColors.textSecondary,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            if (_showManualEntry) ...[
              KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    _processCode(_ctrl.text);
                  }
                },
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  style: const TextStyle(
                    color: OmniGymColors.textPrimary,
                    fontSize: 16,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                  onSubmitted: _processCode,
                  decoration: InputDecoration(
                    hintText: 'Código QR...',
                    hintStyle: const TextStyle(
                        color: OmniGymColors.textSecondary, fontSize: 14),
                    filled: true,
                    fillColor: OmniGymColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: OmniGymColors.border, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: OmniGymColors.border, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: OmniGymColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    suffixIcon: IconButton(
                      onPressed: () => _processCode(_ctrl.text),
                      icon:
                          const Icon(Icons.send, color: OmniGymColors.primary),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (result != null)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: result.isSuccess
                    ? _SuccessCard(member: result.member!)
                    : _ErrorCard(message: result.error!),
              ),
          ],
        ),
      );
    }

    // ── Desktop: text field (lector USB) ────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Control de Acceso',
            style: TextStyle(
              color: OmniGymColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Escanea el QR del socio o ingresa su código manualmente.',
            style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 32),
          const _OwnerBranchSelector(),
          KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                _processCode(_ctrl.text);
              }
            },
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              style: const TextStyle(
                color: OmniGymColors.textPrimary,
                fontSize: 18,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
              onSubmitted: _processCode,
              decoration: InputDecoration(
                hintText: 'Código QR...',
                hintStyle: const TextStyle(
                    color: OmniGymColors.textSecondary, fontSize: 16),
                filled: true,
                fillColor: OmniGymColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: OmniGymColors.border, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: OmniGymColors.border, width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: OmniGymColors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 20, horizontal: 20),
                suffixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: () => _processCode(_ctrl.text),
                        icon:
                            const Icon(Icons.send, color: OmniGymColors.primary),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Presiona Enter o usa un lector QR USB para registrar el acceso.',
            style: TextStyle(color: OmniGymColors.textSecondary, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (result != null)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: result.isSuccess
                  ? _SuccessCard(member: result.member!)
                  : _ErrorCard(message: result.error!),
            ),
        ],
      ),
    );
  }
}

// ─── Selector de sucursal (solo owner/superuser) ───────────────────────────────

class _OwnerBranchSelector extends ConsumerWidget {
  const _OwnerBranchSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    if (role != 'owner' && role != 'superuser') return const SizedBox.shrink();

    final tenantId = ref.watch(activeTenantIdFutureProvider).valueOrNull;
    if (tenantId == null) return const SizedBox.shrink();

    final branchesAsync = ref.watch(branchesProvider(tenantId));
    return branchesAsync.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (branches) {
        if (branches.isEmpty) return const SizedBox.shrink();

        final selected = ref.watch(_selectedScanBranchProvider);
        // Auto-selecciona cuando hay una sola sucursal.
        if (selected == null && branches.length == 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(_selectedScanBranchProvider.notifier).state =
                branches.first.id;
          });
        }
        // Ignora una selección que ya no exista.
        final value = branches.any((b) => b.id == selected) ? selected : null;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: OmniGymColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: OmniGymColors.border, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.store_outlined,
                  color: OmniGymColors.textSecondary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: value,
                    hint: const Text(
                      'Selecciona una sucursal',
                      style: TextStyle(
                          color: OmniGymColors.textSecondary, fontSize: 14),
                    ),
                    dropdownColor: OmniGymColors.surface,
                    style: const TextStyle(
                        color: OmniGymColors.textPrimary, fontSize: 14),
                    items: branches
                        .map((b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(b.name),
                            ))
                        .toList(),
                    onChanged: (id) => ref
                        .read(_selectedScanBranchProvider.notifier)
                        .state = id,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Corners painter ──────────────────────────────────────────────────────────

class _CornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    const margin = 20.0;

    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y + dy * len), Offset(x, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x + dx * len, y), paint);
    }

    corner(margin, margin, 1, 1);
    corner(size.width - margin, margin, -1, 1);
    corner(margin, size.height - margin, 1, -1);
    corner(size.width - margin, size.height - margin, -1, -1);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Tarjeta de resultado OK ──────────────────────────────────────────────────

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final daysLeft = member.expirationDate.difference(DateTime.now()).inDays;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OmniGymColors.success.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OmniGymColors.success.withAlpha(80), width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: OmniGymColors.success.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle,
                color: OmniGymColors.success, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    color: OmniGymColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.verified,
                        color: OmniGymColors.success, size: 14),
                    const SizedBox(width: 4),
                    const Text(
                      'Acceso permitido',
                      style: TextStyle(
                          color: OmniGymColors.success, fontSize: 13),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.calendar_today,
                        color: OmniGymColors.textSecondary, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      '$daysLeft días restantes',
                      style: const TextStyle(
                          color: OmniGymColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tarjeta de error ─────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OmniGymColors.errorRed.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: OmniGymColors.errorRed.withAlpha(80), width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: OmniGymColors.errorRed.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cancel,
                color: OmniGymColors.errorRed, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Acceso denegado',
                  style: TextStyle(
                    color: OmniGymColors.errorRed,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                      color: OmniGymColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Panel de check-ins del día ───────────────────────────────────────────────

class _CheckInsPanel extends ConsumerWidget {
  const _CheckInsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkInsAsync = ref.watch(_recentCheckInsProvider);
    final count = checkInsAsync.valueOrNull?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: OmniGymColors.border)),
          ),
          child: Row(
            children: [
              const Text(
                'Accesos de hoy',
                style: TextStyle(
                  color: OmniGymColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: OmniGymColors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: OmniGymColors.primary.withAlpha(80)),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                      color: OmniGymColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: checkInsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(
                      color: OmniGymColors.textSecondary)),
            ),
            data: (checkIns) => checkIns.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.login,
                            size: 36, color: OmniGymColors.textSecondary),
                        SizedBox(height: 8),
                        Text('Sin accesos registrados hoy.',
                            style: TextStyle(
                                color: OmniGymColors.textSecondary,
                                fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: checkIns.length,
                    separatorBuilder: (context, i) =>
                        const Divider(height: 1, color: OmniGymColors.border),
                    itemBuilder: (_, i) => _CheckInTile(data: checkIns[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CheckInTile extends StatelessWidget {
  const _CheckInTile({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = data['member_name'] as String? ?? '—';
    final ts = data['timestamp'];
    String timeStr = '';
    if (ts != null) {
      final dt = (ts as dynamic).toDate() as DateTime;
      timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: OmniGymColors.success.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check,
                color: OmniGymColors.success, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                  color: OmniGymColors.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(
                color: OmniGymColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
