import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/member.dart';
import '../../core/models/membership_plan.dart';
import '../../core/services/worker_service.dart';

class FacturarDialog extends ConsumerStatefulWidget {
  const FacturarDialog({
    super.key,
    required this.tenantId,
    required this.paymentId,
    required this.member,
    required this.plan,
    required this.amount,
  });

  final String tenantId;
  final String paymentId;
  final Member member;
  final MembershipPlan plan;
  final double amount;

  @override
  ConsumerState<FacturarDialog> createState() => _FacturarDialogState();
}

class _FacturarDialogState extends ConsumerState<FacturarDialog> {
  final _rfcCtrl = TextEditingController();
  final _cpCtrl = TextEditingController();
  bool _facturando = false;
  String? _error;

  @override
  void dispose() {
    _rfcCtrl.dispose();
    _cpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Emitir factura para ${widget.member.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Plan: ${widget.plan.name} - \$${widget.amount.toStringAsFixed(2)} MXN',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rfcCtrl,
            decoration: const InputDecoration(
              labelText: 'RFC del socio',
              hintText: 'XAXX010101000',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cpCtrl,
            decoration: const InputDecoration(
              labelText: 'Código Postal',
              hintText: '01000',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _facturando ? null : () => Navigator.pop(context),
          child: const Text('Después'),
        ),
        FilledButton.icon(
          onPressed: _facturando ? null : _facturar,
          icon: _facturando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.receipt_long, size: 18),
          label: Text(_facturando ? 'Facturando...' : 'Facturar'),
        ),
      ],
    );
  }

  Future<void> _facturar() async {
    setState(() { _error = null; _facturando = true; });

    final result = await WorkerService.timbrarFactura(
      tenantId: widget.tenantId,
      conceptos: [
        {
          'claveProdServ': widget.plan.satProductKey ?? '80111506',
          'claveUnidad': widget.plan.satUnitKey ?? 'E48',
          'descripcion': widget.plan.name,
          'cantidad': 1,
          'valorUnitario': widget.amount,
        }
      ],
      rfc: _rfcCtrl.text.isNotEmpty ? _rfcCtrl.text.toUpperCase() : null,
      nombre: widget.member.name,
      codigoPostal: _cpCtrl.text.isNotEmpty ? _cpCtrl.text : null,
      paymentId: widget.paymentId,
    );

    if (!mounted) return;

    if (result.ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Factura emitida: ${result.uuid}'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      setState(() {
        _facturando = false;
        _error = result.mensaje ?? 'Error al facturar';
      });
    }
  }
}
