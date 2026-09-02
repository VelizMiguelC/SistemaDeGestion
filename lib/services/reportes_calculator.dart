import '../models/android_model.dart';
import '../models/deuda_model.dart';
import '../models/iphone_model.dart';
import '../models/pago_model.dart';

/// Resultado de las funciones de este archivo: ingreso y costo reconocidos
/// en un período, ya combinando ventas de contado y (según la función) la
/// porción cobrada de ventas financiadas.
class IngresosCostoPeriodo {
  final double ingresos;
  final double costo;
  const IngresosCostoPeriodo({required this.ingresos, required this.costo});
}

/// Calcula el ingreso y el costo "reconocidos" en un período.
///
/// El costo se descuenta siempre el día de la venta (`fechaVenta`), sea de
/// contado o financiada -el equipo salió del stock ese día, igual en los
/// dos casos-.
///
/// El ingreso depende de cómo se vendió:
/// - Venta de contado (equipo sin cuenta vinculada en `deudas`): se
///   reconoce íntegro el día de la venta, junto con el costo.
/// - Venta financiada (equipo vinculado a una cuenta vía
///   `idEquipoVinculado`, ver `deuda_model.dart`): el ingreso NO se
///   reconoce en la fecha de venta -queda en $0 hasta que empiece a
///   cobrarse-. Cada pago de esa cuenta (colección `pagos`) reconoce, en la
///   fecha en que se cobró, su monto en pesos convertido a USD con la
///   cotización del dólar blue guardada en ESE pago (`PagoModel.tasaBlue`,
///   cargada al momento de registrarlo -ver `_RegistrarPagoDialog` en
///   finanzas_screen.dart-), no con la cotización de hoy. Así la
///   devaluación del peso mientras la cuenta está en curso no distorsiona
///   el balance. Un pago sin cotización guardada (no debería pasar en pagos
///   nuevos) no se puede convertir y se ignora.
IngresosCostoPeriodo calcularIngresosCosto({
  required List<IPhoneModel> iphones,
  required List<AndroidModel> androids,
  required List<DeudaModel> deudas,
  required List<PagoModel> pagos,
  required bool Function(DateTime fecha) enPeriodo,
}) {
  final deudaPorEquipo = <String, DeudaModel>{
    for (final d in deudas)
      if (d.idEquipoVinculado != null) d.idEquipoVinculado!: d,
  };

  double ingresos = 0;
  double costo = 0;

  for (final e in iphones) {
    if (!e.vendido || e.fechaVenta == null || !enPeriodo(e.fechaVenta!)) continue;
    costo += e.costo;
    if (!deudaPorEquipo.containsKey(e.id)) {
      ingresos += e.precioVenta ?? 0; // venta de contado: ingreso también de una
    }
  }
  for (final e in androids) {
    if (!e.vendido || e.fechaVenta == null || !enPeriodo(e.fechaVenta!)) continue;
    costo += e.costo;
    if (!deudaPorEquipo.containsKey(e.id)) {
      ingresos += e.precioVenta ?? 0;
    }
  }

  final deudaPorId = <String, DeudaModel>{for (final d in deudas) d.id: d};
  for (final pago in pagos) {
    final deuda = deudaPorId[pago.idDeuda];
    if (deuda == null || deuda.idEquipoVinculado == null) continue;
    if (!enPeriodo(pago.fechaPago)) continue;
    final tasa = pago.tasaBlue;
    if (tasa == null || tasa <= 0) continue; // sin cotización guardada: no se puede convertir
    ingresos += pago.montoAbonado / tasa;
  }

  return IngresosCostoPeriodo(ingresos: ingresos, costo: costo);
}

/// Variante "operativa" de [calcularIngresosCosto], usada solo para el
/// gráfico de Ganancia operativa (`_GananciaOperativaChart` en
/// reportes_screen.dart).
///
/// Acá el costo de una venta financiada TAMBIÉN se reparte a medida que se
/// cobra cada cuota -en la misma proporción que representa el pago sobre
/// el total de la cuenta en pesos, un cociente sin unidades que no mezcla
/// monedas-, en vez de descontarse entero el día de la venta.
///
/// Sirve para ver mes a mes cuánto generó el negocio realmente sin que una
/// venta financiada grande aparezca como "pérdida" el mes en que se vendió
/// sin haber cobrado nada todavía -esa distinción más conservadora (costo
/// completo al vender) es justamente la que ya muestran los KPIs de arriba
/// y [calcularIngresosCosto]-.
IngresosCostoPeriodo calcularIngresosCostoSuavizado({
  required List<IPhoneModel> iphones,
  required List<AndroidModel> androids,
  required List<DeudaModel> deudas,
  required List<PagoModel> pagos,
  required bool Function(DateTime fecha) enPeriodo,
}) {
  final deudaPorEquipo = <String, DeudaModel>{
    for (final d in deudas)
      if (d.idEquipoVinculado != null) d.idEquipoVinculado!: d,
  };
  final costoPorEquipo = <String, double>{
    for (final e in iphones) e.id: e.costo,
    for (final e in androids) e.id: e.costo,
  };

  double ingresos = 0;
  double costo = 0;

  for (final e in iphones) {
    if (!e.vendido || e.fechaVenta == null) continue;
    if (deudaPorEquipo.containsKey(e.id)) continue; // financiada: se reparte por pago
    if (!enPeriodo(e.fechaVenta!)) continue;
    ingresos += e.precioVenta ?? 0;
    costo += e.costo;
  }
  for (final e in androids) {
    if (!e.vendido || e.fechaVenta == null) continue;
    if (deudaPorEquipo.containsKey(e.id)) continue;
    if (!enPeriodo(e.fechaVenta!)) continue;
    ingresos += e.precioVenta ?? 0;
    costo += e.costo;
  }

  final deudaPorId = <String, DeudaModel>{for (final d in deudas) d.id: d};
  for (final pago in pagos) {
    final deuda = deudaPorId[pago.idDeuda];
    if (deuda == null || deuda.idEquipoVinculado == null) continue;
    if (!enPeriodo(pago.fechaPago)) continue;
    final tasa = pago.tasaBlue;
    if (tasa == null || tasa <= 0) continue;
    if (deuda.montoTotal <= 0) continue;
    final costoEquipo = costoPorEquipo[deuda.idEquipoVinculado];
    if (costoEquipo == null) continue;
    ingresos += pago.montoAbonado / tasa;
    costo += (pago.montoAbonado / deuda.montoTotal) * costoEquipo;
  }

  return IngresosCostoPeriodo(ingresos: ingresos, costo: costo);
}

/// Ingreso y costo de las ventas **de contado únicamente**: a diferencia de
/// [calcularIngresosCosto] y [calcularIngresosCostoSuavizado], acá un
/// equipo financiado (vinculado a una cuenta, esté pagada o no) se excluye
/// por completo -no se cuenta ni su costo ni su ingreso, ni siquiera
/// prorrateado-.
///
/// Sirve para la sección "Solo ventas de contado" de Reportes: una foto
/// simple de lo que realmente vendiste y cobraste, sin el ruido de que un
/// equipo financiado aparezca descontando costo antes de haber cobrado
/// nada.
IngresosCostoPeriodo calcularIngresosCostoContado({
  required List<IPhoneModel> iphones,
  required List<AndroidModel> androids,
  required List<DeudaModel> deudas,
  required bool Function(DateTime fecha) enPeriodo,
}) {
  final idsFinanciados = <String>{
    for (final d in deudas)
      if (d.idEquipoVinculado != null) d.idEquipoVinculado!,
  };

  double ingresos = 0;
  double costo = 0;

  for (final e in iphones) {
    if (!e.vendido || e.fechaVenta == null) continue;
    if (idsFinanciados.contains(e.id)) continue;
    if (!enPeriodo(e.fechaVenta!)) continue;
    ingresos += e.precioVenta ?? 0;
    costo += e.costo;
  }
  for (final e in androids) {
    if (!e.vendido || e.fechaVenta == null) continue;
    if (idsFinanciados.contains(e.id)) continue;
    if (!enPeriodo(e.fechaVenta!)) continue;
    ingresos += e.precioVenta ?? 0;
    costo += e.costo;
  }

  return IngresosCostoPeriodo(ingresos: ingresos, costo: costo);
}
