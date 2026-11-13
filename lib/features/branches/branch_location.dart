import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/branch.dart';

Uri? branchLocationUrl(Branch branch) {
  final location = branch.location;
  final address = branch.address;
  final validCoordinates =
      location != null &&
      location.latitude.isFinite &&
      location.longitude.isFinite &&
      location.latitude.abs() <= 90 &&
      location.longitude.abs() <= 180;
  String query;
  if (validCoordinates) {
    query = '${location.latitude},${location.longitude}';
  } else if (address != null && address.street.trim().isNotEmpty) {
    query = [
      address.street,
      address.colonia ?? '',
      address.municipality ?? '',
      address.city,
      address.state,
      address.postalCode,
      address.country,
    ].map((part) => part.trim()).where((part) => part.isNotEmpty).join(', ');
  } else {
    return null;
  }
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
}

class BranchLocationDialog extends StatefulWidget {
  const BranchLocationDialog({super.key, required this.branch});
  final Branch branch;

  @override
  State<BranchLocationDialog> createState() => _BranchLocationDialogState();
}

class _BranchLocationDialogState extends State<BranchLocationDialog> {
  bool _sharing = false;
  String? _message;

  Future<void> _copy(Uri url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url.toString()));
      if (mounted) setState(() => _message = 'Enlace copiado.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Selecciona y copia el enlace.');
    }
  }

  Future<void> _open(Uri url) async {
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // The link remains selectable if the platform cannot open Maps.
    }
    if (mounted) {
      setState(() => _message = 'Copia el enlace para abrirlo en Maps.');
    }
  }

  Future<void> _share(BuildContext buttonContext, Uri url) async {
    final box = buttonContext.findRenderObject() as RenderBox;
    setState(() {
      _sharing = true;
      _message = null;
    });
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: widget.branch.name,
          text: '${widget.branch.name}\n$url',
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Compartir no está disponible. Usa Copiar enlace.',
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = branchLocationUrl(widget.branch);
    return AlertDialog(
      title: Text('Ubicación de ${widget.branch.name}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (url == null)
              const Text(
                'Agrega una dirección o un punto en el mapa de la sucursal.',
              )
            else
              SelectableText(url.toString()),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_message!)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (url != null) ...[
          TextButton(
            onPressed: () => _open(url),
            child: const Text('Google Maps'),
          ),
          TextButton(
            onPressed: () => _copy(url),
            child: const Text('Copiar enlace'),
          ),
          Builder(
            builder: (buttonContext) => FilledButton.icon(
              onPressed: _sharing ? null : () => _share(buttonContext, url),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Compartir'),
            ),
          ),
        ],
      ],
    );
  }
}
