import 'dart:io' show File, Directory, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/factura.dart';
import '../../core/providers/providers.dart';
import '../../core/services/worker_service.dart';

class FacturacionScreen extends ConsumerWidget {
  const FacturacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantIdAsync = ref.watch(activeTenantIdFutureProvider);
    final colors = Theme.of(context).colorScheme;

    return tenantIdAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (tenantId) {
        if (tenantId == null) {
          return const Center(child: Text('No hay tenant activo'));
        }

        final facturasAsync = ref.watch(tenantFacturasProvider(tenantId));

        return Scaffold(
          appBar: AppBar(title: const Text('Facturación')),
          body: facturasAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (facturas) {
              if (facturas.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long,
                          size: 64, color: colors.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('Sin facturas emitidas',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                );
              }

              final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: facturas.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _FacturaRow(
                  factura: facturas[i],
                  fmt: fmt,
                  tenantId: tenantId,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FacturaRow extends ConsumerWidget {
  const _FacturaRow({
    required this.factura,
    required this.fmt,
    required this.tenantId,
  });

  final Factura factura;
  final NumberFormat fmt;
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final date = factura.createdAt != null
        ? DateFormat('dd/MM/yy HH:mm').format(factura.createdAt!)
        : factura.fecha ?? '';
    final vigente = factura.status == 'vigente';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  vigente ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: vigente ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    factura.uuid.substring(0, 8),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
                Text(
                  fmt.format(factura.total ?? 0),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _Tag(
                  '${factura.serie ?? ''}${factura.folio ?? ''}',
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    factura.receptorNombre ?? factura.receptorRfc ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(date,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.onSurface.withValues(alpha: 0.5))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionChip(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF',
                  onTap: () => _abrirPdf(context, tenantId, factura.uuid),
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.code,
                  label: 'XML',
                  onTap: () => _descargarXml(context, ref, tenantId, factura.uuid),
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  onTap: () => _enviarEmail(context, tenantId, factura),
                ),
                if (vigente) ...[
                  const SizedBox(width: 8),
                  _ActionChip(
                    icon: Icons.cancel_outlined,
                    label: 'Cancelar',
                    color: Colors.red,
                    onTap: () => _confirmarCancelar(
                        context, ref, tenantId, factura.uuid),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirPdf(BuildContext context, String tenantId, String uuid) async {
    // Web: abrir con URL autenticada (worker acepta ?token=)
    if (kIsWeb) {
      final url = WorkerService.urlPdf(tenantId: tenantId, uuid: uuid);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    // Mobile/Desktop: descargar bytes y abrir archivo local
    try {
      final bytes = await WorkerService.descargarPdf(tenantId: tenantId, uuid: uuid);
      if (bytes == null || !context.mounted) return;

      final dir = Platform.isAndroid || Platform.isIOS
          ? Directory.systemTemp
          : Directory(_downloadsPath());
      if (!await dir.exists()) await dir.create(recursive: true);

      final file = File('${dir.path}/factura_$uuid.pdf');
      await file.writeAsBytes(bytes);

      if (context.mounted) {
        await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir PDF: $e')),
        );
      }
    }
  }

  String _downloadsPath() {
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/Downloads';
    }
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? 'C:\\';
      return '$home\\Downloads';
    }
    return '/tmp';
  }

  Future<void> _descargarXml(
      BuildContext context, WidgetRef ref, String tenantId, String uuid) async {
    final xml = await WorkerService.descargarXml(tenantId: tenantId, uuid: uuid);
    if (!context.mounted) return;

    if (xml == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al descargar XML')),
      );
      return;
    }

    if (kIsWeb) {
      // Web: usar URL autenticada
      final url = '${WorkerService.urlPdf(tenantId: tenantId, uuid: uuid).replaceAll('format=pdf', 'format=xml')}';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    try {
      final dir = Platform.isAndroid || Platform.isIOS
          ? Directory.systemTemp
          : Directory(_downloadsPath());
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/factura_$uuid.xml');
      await file.writeAsString(xml);
      if (context.mounted) {
        await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('XML descargado'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _enviarEmail(
      BuildContext context, String tenantId, Factura factura) async {
    final emailCtrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar factura por email'),
        content: TextField(
          controller: emailCtrl,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'cliente@email.com',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    emailCtrl.dispose();

    if (email != null && email.isNotEmpty && context.mounted) {
      final ok = await WorkerService.enviarFacturaEmail(
        tenantId: tenantId, uuid: factura.uuid, email: email,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Factura enviada a $email' : 'Error al enviar'),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmarCancelar(
      BuildContext context, WidgetRef ref, String tenantId, String uuid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar factura'),
        content: Text('¿Cancelar $uuid? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      final result = await WorkerService.cancelarFactura(
        tenantId: tenantId, uuid: uuid,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.ok ? 'Factura cancelada' : result.mensaje ?? 'Error'),
          ),
        );
      }
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: c)),
          ],
        ),
      ),
    );
  }
}
