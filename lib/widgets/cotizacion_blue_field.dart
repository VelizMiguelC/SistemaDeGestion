import 'package:flutter/material.dart';

import '../services/dolar_blue_service.dart';

/// Campo reutilizable que busca sola la cotización del dólar blue (venta)
/// al montarse, y si falla deja cargarla a mano como respaldo -con botón
/// de "Reintentar"-.
///
/// Notifica a quien lo usa la cotización a aplicar vía [onTasaResuelta]:
/// `null` mientras se está buscando, si la consulta falló y todavía no se
/// cargó nada a mano, o si el valor manual escrito no es un número válido.
///
/// Usado tanto en `_RegistrarPagoDialog` (finanzas_screen.dart) como en
/// `_MarcarVendidoDialog` (iphones_screen.dart / android_screen.dart)
/// cuando hay que convertir un monto en pesos a USD.
class CotizacionBlueField extends StatefulWidget {
  final ValueChanged<double?> onTasaResuelta;
  const CotizacionBlueField({super.key, required this.onTasaResuelta});

  @override
  State<CotizacionBlueField> createState() => _CotizacionBlueFieldState();
}

class _CotizacionBlueFieldState extends State<CotizacionBlueField> {
  final _manualCtrl = TextEditingController();
  bool _buscando = true;
  double? _automatica;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    setState(() => _buscando = true);
    widget.onTasaResuelta(null);
    // Además del timeout propio de DolarBlueService, este límite duro
    // garantiza que el spinner nunca quede pegado pase lo que pase (por
    // ejemplo, si el pedido queda colgado a nivel navegador sin disparar
    // ninguna excepción Dart) -si tarda más de 10s, se trata igual que una
    // consulta fallida y se ofrece cargar la cotización a mano-.
    final tasa = await Future.any<double?>([
      DolarBlueService().obtenerCotizacionVenta(),
      Future.delayed(const Duration(seconds: 10), () => null),
    ]);
    if (!mounted) return;
    setState(() {
      _buscando = false;
      _automatica = tasa;
    });
    widget.onTasaResuelta(tasa);
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_buscando) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Buscando cotización del dólar blue...', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    if (_automatica != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Cotización blue (venta): \$${_automatica!.toStringAsFixed(0)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    // Falló la consulta automática: se carga a mano, es obligatoria.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'No se pudo obtener la cotización automáticamente',
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
            TextButton(onPressed: _buscar, child: const Text('Reintentar')),
          ],
        ),
        TextFormField(
          controller: _manualCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Cotización dólar blue (a mano)'),
          onChanged: (value) {
            widget.onTasaResuelta(double.tryParse(value.trim().replaceAll(',', '.')));
          },
          validator: (value) {
            final n = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
            if (n == null || n <= 0) return 'Cargá la cotización de hoy';
            return null;
          },
        ),
      ],
    );
  }
}
