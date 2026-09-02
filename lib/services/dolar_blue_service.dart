import 'dart:convert';

import 'package:http/http.dart' as http;

/// Cotización del dólar blue en un momento dado.
class CotizacionBlue {
  final double compra;
  final double venta;
  const CotizacionBlue({required this.compra, required this.venta});
}

/// Consulta la cotización del dólar blue en dolarapi.com (API pública,
/// gratuita, sin necesidad de clave). Se usa para:
/// - Convertir a USD los pagos de cuentas financiadas al momento en que se
///   cobran (ver `_RegistrarPagoDialog` en finanzas_screen.dart y
///   `_calcularIngresosCosto`/`_calcularIngresosCostoSuavizado` en
///   reportes_screen.dart).
/// - Mostrar la cotización actual en el chip del Dashboard
///   (`_DolarBlueChip`).
///
/// Devuelve `null` si la consulta falla (sin internet, API caída, etc.) en
/// vez de lanzar una excepción -quien llama debe manejar ese caso (por
/// ejemplo, ofreciendo cargar la cotización a mano como respaldo)-.
class DolarBlueService {
  static const _url = 'https://dolarapi.com/v1/dolares/blue';

  Future<CotizacionBlue?> obtenerCotizacion() async {
    try {
      final respuesta = await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 8));
      if (respuesta.statusCode != 200) return null;
      final data = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final compra = data['compra'];
      final venta = data['venta'];
      if (compra is num && venta is num) {
        return CotizacionBlue(compra: compra.toDouble(), venta: venta.toDouble());
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<double?> obtenerCotizacionVenta() async {
    final cotizacion = await obtenerCotizacion();
    return cotizacion?.venta;
  }
}
