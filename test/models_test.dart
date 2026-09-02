import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_app/models/deuda_model.dart';
import 'package:inventario_app/models/iphone_model.dart';
import 'package:inventario_app/models/pago_model.dart';

void main() {
  group('DeudaModel', () {
    DeudaModel deuda({
      double montoTotal = 100,
      double montoAbonado = 0,
      String estado = 'pendiente',
      String? idEquipoVinculado,
    }) {
      return DeudaModel(
        id: 'd1',
        idCliente: 'c1',
        montoTotal: montoTotal,
        montoAbonado: montoAbonado,
        fechaEmision: DateTime(2026, 1, 1),
        estado: estado,
        idEquipoVinculado: idEquipoVinculado,
      );
    }

    test('saldoPendiente resta lo abonado del total', () {
      expect(deuda(montoTotal: 1000, montoAbonado: 300).saldoPendiente, 700);
    });

    test('estaSaldada es true apenas el saldo llega a cero o menos', () {
      expect(deuda(montoTotal: 1000, montoAbonado: 1000).estaSaldada, isTrue);
      expect(deuda(montoTotal: 1000, montoAbonado: 999).estaSaldada, isFalse);
    });

    test('pagada acepta variantes de mayúscula/acento de datos importados', () {
      expect(deuda(estado: 'pagado').pagada, isTrue);
      expect(deuda(estado: 'Pagada').pagada, isTrue);
      expect(deuda(estado: 'PENDIENTE').pagada, isFalse);
    });

    test('esVentaFinanciada refleja si hay un equipo vinculado', () {
      expect(deuda().esVentaFinanciada, isFalse);
      expect(deuda(idEquipoVinculado: 'iphone-1').esVentaFinanciada, isTrue);
    });

    test('toMap/fromMap conservan idEquipoVinculado y tipoEquipoVinculado', () {
      final original = DeudaModel(
        id: 'd2',
        idCliente: 'c1',
        montoTotal: 500,
        fechaEmision: DateTime(2026, 2, 1),
        idEquipoVinculado: 'iphone-9',
        tipoEquipoVinculado: 'iphone',
      );
      final reconstruido = DeudaModel.fromMap(original.toMap(), original.id);
      expect(reconstruido.idEquipoVinculado, 'iphone-9');
      expect(reconstruido.tipoEquipoVinculado, 'iphone');
      expect(reconstruido.esVentaFinanciada, isTrue);
    });

    test('copyWith no pierde la vinculación si no se pasa explícitamente', () {
      final original = deuda(idEquipoVinculado: 'iphone-1');
      final copia = original.copyWith(nota: 'corregido');
      expect(copia.idEquipoVinculado, 'iphone-1');
    });
  });

  group('IPhoneModel', () {
    IPhoneModel iphone({
      double costo = 500,
      double? precioVenta,
      bool esCompartido = false,
      double? porcentajeSocio,
    }) {
      return IPhoneModel(
        id: 'i1',
        imei: '123456789012345',
        modelo: 'iPhone 13',
        capacidad: '128GB',
        color: 'Negro',
        bateria: 100,
        estado: EstadoIPhone.usado,
        costo: costo,
        precioVenta: precioVenta,
        esCompartido: esCompartido,
        porcentajeSocio: porcentajeSocio,
      );
    }

    test('ganancia es null sin precio de venta cargado', () {
      expect(iphone(precioVenta: null).ganancia, isNull);
    });

    test('ganancia es precioVenta menos costo', () {
      expect(iphone(costo: 500, precioVenta: 800).ganancia, 300);
    });

    test('sin socio, gananciaPropia es toda la ganancia', () {
      expect(iphone(costo: 500, precioVenta: 800).gananciaPropia, 300);
    });

    test('con socio, se descuenta su porcentaje de la ganancia propia', () {
      final e = iphone(costo: 500, precioVenta: 800, esCompartido: true, porcentajeSocio: 40);
      expect(e.gananciaSocio, closeTo(120, 0.001)); // 40% de 300
      expect(e.gananciaPropia, closeTo(180, 0.001)); // 300 - 120
    });
  });

  group('PagoModel', () {
    test('toMap/fromMap conservan tasaBlue', () {
      final original = PagoModel(
        id: 'p1',
        idDeuda: 'd1',
        fechaPago: DateTime(2026, 4, 5),
        montoAbonado: 60000,
        tasaBlue: 1234.5,
      );
      final reconstruido = PagoModel.fromMap(original.toMap(), original.id);
      expect(reconstruido.tasaBlue, 1234.5);
      expect(reconstruido.montoAbonado, 60000);
    });

    test('tasaBlue es null si nunca se guardó (pagos de cuentas no financiadas)', () {
      final map = {
        'idDeuda': 'd1',
        'fechaPago': Timestamp.fromDate(DateTime(2026, 4, 5)),
        'montoAbonado': 5000,
        'metodoPago': 'efectivo',
        'nota': '',
      };
      final pago = PagoModel.fromMap(map, 'p2');
      expect(pago.tasaBlue, isNull);
    });
  });
}
