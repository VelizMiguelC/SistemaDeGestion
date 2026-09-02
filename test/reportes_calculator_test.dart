import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_app/models/android_model.dart';
import 'package:inventario_app/models/deuda_model.dart';
import 'package:inventario_app/models/iphone_model.dart';
import 'package:inventario_app/models/pago_model.dart';
import 'package:inventario_app/services/reportes_calculator.dart';

/// Estos tests cubren la lógica que ya rompió en producción una vez (venta
/// financiada contada como si fuera de contado por falta de vínculo, y
/// pesos mezclados con dólares) — la idea es que un cambio futuro en estos
/// cálculos no pueda volver a romper eso sin que un test lo marque.
void main() {
  // Período "todo el año 2026" para no tener que pelear con filtros de mes
  // en la mayoría de los casos.
  bool en2026(DateTime fecha) => fecha.year == 2026;

  IPhoneModel iphone({
    required String id,
    required double costo,
    double? precioVenta,
    bool vendido = true,
    DateTime? fechaVenta,
  }) {
    return IPhoneModel(
      id: id,
      imei: '000000000000$id',
      modelo: 'iPhone 13',
      capacidad: '128GB',
      color: 'Negro',
      bateria: 100,
      estado: EstadoIPhone.usado,
      costo: costo,
      precioVenta: precioVenta,
      vendido: vendido,
      fechaVenta: fechaVenta ?? DateTime(2026, 3, 10),
    );
  }

  DeudaModel deudaFinanciada({
    required String id,
    required String idEquipo,
    required double montoTotal,
    double montoAbonado = 0,
  }) {
    return DeudaModel(
      id: id,
      idCliente: 'cliente-1',
      montoTotal: montoTotal,
      montoAbonado: montoAbonado,
      fechaEmision: DateTime(2026, 3, 10),
      idEquipoVinculado: idEquipo,
      tipoEquipoVinculado: 'iphone',
    );
  }

  PagoModel pago({
    required String idDeuda,
    required double monto,
    double? tasaBlue,
    DateTime? fecha,
  }) {
    return PagoModel(
      id: 'pago-${idDeuda}_$monto',
      idDeuda: idDeuda,
      fechaPago: fecha ?? DateTime(2026, 4, 5),
      montoAbonado: monto,
      tasaBlue: tasaBlue,
    );
  }

  group('calcularIngresosCosto (vista principal, costo íntegro al vender)', () {
    test('venta de contado: ingreso y costo completos el día de la venta', () {
      final equipo = iphone(id: '1', costo: 500, precioVenta: 800);
      final resultado = calcularIngresosCosto(
        iphones: [equipo],
        androids: const [],
        deudas: const [],
        pagos: const [],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 800);
      expect(resultado.costo, 500);
    });

    test('venta financiada sin pagos todavía: costo se descuenta, ingreso en cero', () {
      final equipo = iphone(id: '2', costo: 500, precioVenta: 800);
      final deuda = deudaFinanciada(id: 'd1', idEquipo: '2', montoTotal: 780000);
      final resultado = calcularIngresosCosto(
        iphones: [equipo],
        androids: const [],
        deudas: [deuda],
        pagos: const [],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 0);
      expect(resultado.costo, 500);
    });

    test('venta financiada con un pago: ingreso se reconoce vía pago/tasaBlue, no vía pesos', () {
      final equipo = iphone(id: '3', costo: 500, precioVenta: 800);
      final deuda = deudaFinanciada(id: 'd2', idEquipo: '3', montoTotal: 780000, montoAbonado: 60000);
      final abono = pago(idDeuda: 'd2', monto: 60000, tasaBlue: 1000);
      final resultado = calcularIngresosCosto(
        iphones: [equipo],
        androids: const [],
        deudas: [deuda],
        pagos: [abono],
        enPeriodo: en2026,
      );
      // 60.000 pesos / 1.000 (blue) = USD 60. NUNCA debe dar 60.000 (eso
      // sería sumar pesos directo al total en dólares).
      expect(resultado.ingresos, 60);
      expect(resultado.costo, 500); // costo íntegro, ya se contó al vender
    });

    test('pago sin cotización guardada se ignora (no se puede convertir)', () {
      final equipo = iphone(id: '4', costo: 500, precioVenta: 800);
      final deuda = deudaFinanciada(id: 'd3', idEquipo: '4', montoTotal: 780000, montoAbonado: 60000);
      final abono = pago(idDeuda: 'd3', monto: 60000, tasaBlue: null);
      final resultado = calcularIngresosCosto(
        iphones: [equipo],
        androids: const [],
        deudas: [deuda],
        pagos: [abono],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 0);
    });

    test('la cotización usada es la del pago, no una tasa "de hoy"', () {
      final equipo = iphone(id: '5', costo: 500, precioVenta: 800);
      final deuda = deudaFinanciada(id: 'd4', idEquipo: '5', montoTotal: 780000, montoAbonado: 120000);
      final pagoViejo = pago(idDeuda: 'd4', monto: 60000, tasaBlue: 1000, fecha: DateTime(2026, 3, 15));
      final pagoNuevo = pago(idDeuda: 'd4', monto: 60000, tasaBlue: 1500, fecha: DateTime(2026, 6, 15));
      final resultado = calcularIngresosCosto(
        iphones: [equipo],
        androids: const [],
        deudas: [deuda],
        pagos: [pagoViejo, pagoNuevo],
        enPeriodo: en2026,
      );
      // 60/1000 + 60000/1500 = 60 + 40 = 100 -no 120, que sería usar la
      // misma tasa para los dos pagos-.
      expect(resultado.ingresos, 100);
    });

    test('equipo vendido fuera del período no cuenta', () {
      final equipo = iphone(id: '6', costo: 500, precioVenta: 800, fechaVenta: DateTime(2025, 12, 1));
      final resultado = calcularIngresosCosto(
        iphones: [equipo],
        androids: const [],
        deudas: const [],
        pagos: const [],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 0);
      expect(resultado.costo, 0);
    });

    test('equipo todavía no vendido no cuenta', () {
      final equipo = iphone(id: '7', costo: 500, precioVenta: 800, vendido: false);
      final resultado = calcularIngresosCosto(
        iphones: [equipo],
        androids: const [],
        deudas: const [],
        pagos: const [],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 0);
      expect(resultado.costo, 0);
    });

    test('combina iPhones y Android', () {
      final iph = iphone(id: '8', costo: 500, precioVenta: 800);
      final and = AndroidModel(
        id: 'a1',
        marca: 'Samsung',
        modelo: 'S23',
        almacenamiento: '128GB',
        ram: '8GB',
        color: 'Negro',
        estado: EstadoAndroid.usado,
        costo: 300,
        precioVenta: 500,
        vendido: true,
        fechaVenta: DateTime(2026, 5, 1),
      );
      final resultado = calcularIngresosCosto(
        iphones: [iph],
        androids: [and],
        deudas: const [],
        pagos: const [],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 1300);
      expect(resultado.costo, 800);
    });
  });

  group('calcularIngresosCostoSuavizado (costo también prorrateado)', () {
    test('sin pagos todavía: ni costo ni ingreso (a diferencia de la vista principal)', () {
      final equipo = iphone(id: '9', costo: 500, precioVenta: 800);
      final deuda = deudaFinanciada(id: 'd5', idEquipo: '9', montoTotal: 780000);
      final resultado = calcularIngresosCostoSuavizado(
        iphones: [equipo],
        androids: const [],
        deudas: [deuda],
        pagos: const [],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 0);
      expect(resultado.costo, 0);
    });

    test('costo se reparte en la misma proporción que el pago sobre el total en pesos', () {
      final equipo = iphone(id: '10', costo: 500, precioVenta: 800);
      // Pago de 78.000 sobre un total de 780.000 = 10% de la cuenta.
      final deuda = deudaFinanciada(id: 'd6', idEquipo: '10', montoTotal: 780000, montoAbonado: 78000);
      final abono = pago(idDeuda: 'd6', monto: 78000, tasaBlue: 1000);
      final resultado = calcularIngresosCostoSuavizado(
        iphones: [equipo],
        androids: const [],
        deudas: [deuda],
        pagos: [abono],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 78); // 78.000 / 1.000
      expect(resultado.costo, 50); // 10% de 500
    });

    test('venta de contado se comporta igual que en la vista principal', () {
      final equipo = iphone(id: '11', costo: 500, precioVenta: 800);
      final resultado = calcularIngresosCostoSuavizado(
        iphones: [equipo],
        androids: const [],
        deudas: const [],
        pagos: const [],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 800);
      expect(resultado.costo, 500);
    });
  });

  group('calcularIngresosCostoContado (excluye financiadas por completo)', () {
    test('excluye el equipo financiado aunque tenga pagos', () {
      final contado = iphone(id: '12', costo: 500, precioVenta: 800);
      final financiado = iphone(id: '13', costo: 400, precioVenta: 700);
      final deuda = deudaFinanciada(id: 'd7', idEquipo: '13', montoTotal: 700000, montoAbonado: 700000);
      final resultado = calcularIngresosCostoContado(
        iphones: [contado, financiado],
        androids: const [],
        deudas: [deuda],
        enPeriodo: en2026,
      );
      // Solo el equipo de contado, aunque el financiado ya esté saldado.
      expect(resultado.ingresos, 800);
      expect(resultado.costo, 500);
    });

    test('sin ventas financiadas, es igual a sumar todo lo vendido', () {
      final a = iphone(id: '14', costo: 500, precioVenta: 800);
      final b = iphone(id: '15', costo: 300, precioVenta: 600);
      final resultado = calcularIngresosCostoContado(
        iphones: [a, b],
        androids: const [],
        deudas: const [],
        enPeriodo: en2026,
      );
      expect(resultado.ingresos, 1400);
      expect(resultado.costo, 800);
    });
  });
}
