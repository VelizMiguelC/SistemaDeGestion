import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_parsing.dart';
import 'pago_model.dart';

enum TipoDeuda { deudor, acreedor }

extension TipoDeudaExtension on TipoDeuda {
  String get label {
    switch (this) {
      case TipoDeuda.deudor:
        return 'Deudor';
      case TipoDeuda.acreedor:
        return 'Acreedor';
    }
  }

  static TipoDeuda fromString(String value) =>
      TipoDeuda.values.firstWhere((e) => e.name == value, orElse: () => TipoDeuda.deudor);
}

/// Modelo de una cuenta (deuda a favor o en contra) vinculada a un cliente.
///
/// Esquema alineado con la importación masiva desde
/// 'DEUDAS Y DEUDORES.xlsx' (colección `deudas`, doc ID = `ID_Deuda`):
/// `idCliente`, `concepto`, `montoTotal`, `fechaEmision`, `estado`.
///
/// Además conserva campos propios de la app (no forman parte del esquema de
/// importación, pero son necesarios para no perder funcionalidad existente):
/// `tipo` (deudor/acreedor, para separar "Me deben" de "Debo"),
/// `montoAbonado` (total abonado hasta ahora, se actualiza al registrar
/// pagos), `numeroDeuda` (identificador corto legible), `nota` y
/// `fechaPago` (cuándo se saldó la cuenta, si corresponde).
///
/// `estado` usa los valores binarios 'pendiente'/'pagado' (en minúscula).
/// Documentos ya existentes importados desde Excel pueden tener
/// 'Pendiente'/'Pagada' (con mayúscula, sin acento) — usar el getter
/// [pagada] en vez de comparar `estado` directamente, ya que es
/// insensible a mayúsculas/variantes.
class DeudaModel {
  final String id;
  final String idCliente;
  final TipoDeuda tipo;
  final String concepto;
  final double montoTotal;
  final double montoAbonado;
  final DateTime fechaEmision;
  final String estado;
  final DateTime? fechaPago;
  final String numeroDeuda;
  final String nota;

  /// Si esta cuenta se generó al marcar un equipo como vendido "financiado
  /// (en cuotas)" (ver `_MarcarVendidoDialog` en iphones_screen.dart /
  /// android_screen.dart), acá queda el id de ese equipo y su tipo
  /// ('iphone' o 'android'). `null` en el resto de las cuentas (alta manual
  /// desde Finanzas, o importadas desde Excel).
  ///
  /// Esta vinculación es la que le permite a `reportes_screen.dart`
  /// reconocer el ingreso/ganancia de una venta financiada a medida que se
  /// cobra cada cuota (en `pagos`), en vez de contar el precio de venta
  /// completo el día de la venta.
  final String? idEquipoVinculado;
  final String? tipoEquipoVinculado;

  /// Historial de pagos/abonos de esta cuenta, en memoria.
  ///
  /// La fuente de verdad sigue siendo la colección de nivel superior
  /// `pagos` (cada documento con su propio `idDeuda`) — igual que en la
  /// importación desde Excel y que `DeudaProvider.registrarPago` — en vez
  /// de un arreglo embebido en el documento de la deuda: así los abonos
  /// parciales se pueden sumar/editar/eliminar de forma atómica sin
  /// reescribir todo el documento, y no se choca con el límite de 1&nbsp;MiB
  /// por documento de Firestore si una cuenta acumula muchos pagos.
  ///
  /// Este campo es opcional y `null` por defecto: `fromMap`/`toMap` no lo
  /// leen ni lo escriben. Se usa para llevar el historial ya cargado junto
  /// a la deuda cuando conviene (por ejemplo, al procesar una importación
  /// JSON que trae los pagos embebidos); para mostrarlo en pantalla, ver
  /// `PagoProvider.porDeuda`.
  final List<PagoModel>? pagos;

  const DeudaModel({
    required this.id,
    required this.idCliente,
    this.tipo = TipoDeuda.deudor,
    this.concepto = '',
    required this.montoTotal,
    this.montoAbonado = 0,
    required this.fechaEmision,
    this.estado = 'pendiente',
    this.fechaPago,
    this.numeroDeuda = '',
    this.nota = '',
    this.pagos,
    this.idEquipoVinculado,
    this.tipoEquipoVinculado,
  });

  double get saldoPendiente => montoTotal - montoAbonado;
  bool get estaSaldada => saldoPendiente <= 0;

  /// `true` si esta cuenta corresponde a la venta financiada de un equipo
  /// (en vez de una deuda/cuenta cargada manualmente).
  bool get esVentaFinanciada => idEquipoVinculado != null;

  /// Alias de [fechaEmision], para coincidir con el nombre pedido en el
  /// esquema binario pendiente/pagado ("fechaCreacion").
  DateTime get fechaCreacion => fechaEmision;

  /// Alias de [fechaEmision], para mantener compatibilidad de lectura con
  /// el nombre usado anteriormente ("fecha") en el resto de la app.
  DateTime get fecha => fechaEmision;

  /// `true` si `estado` indica que la cuenta está saldada. Acepta
  /// 'pagado'/'pagada' sin distinguir mayúsculas, para ser compatible con
  /// datos ya existentes (por ejemplo, importados antes de este cambio).
  bool get pagada {
    final valor = estado.trim().toLowerCase();
    return valor == 'pagado' || valor == 'pagada';
  }

  factory DeudaModel.fromMap(Map<String, dynamic> map, String documentId) {
    return DeudaModel(
      id: documentId,
      idCliente: (map['idCliente'] ?? '').toString(),
      tipo: TipoDeudaExtension.fromString((map['tipo'] ?? 'deudor').toString()),
      concepto: (map['concepto'] ?? '').toString(),
      montoTotal: leerMontoFirestore(map['montoTotal']) ?? 0,
      montoAbonado: leerMontoFirestore(map['montoAbonado']) ?? 0,
      fechaEmision: leerFechaFirestore(map['fechaEmision']) ?? DateTime.now(),
      estado: (map['estado'] ?? 'pendiente').toString(),
      fechaPago: leerFechaFirestore(map['fechaPago']),
      numeroDeuda: (map['numeroDeuda'] ?? '').toString(),
      nota: (map['nota'] ?? '').toString(),
      // Fallback de compatibilidad: si el documento trae un campo `pagos`
      // embebido como array (por ejemplo, por una carga manual en la
      // consola de Firebase) en vez de -o además de- documentos en la
      // colección de nivel superior `pagos`, se parsea acá para que el
      // historial de pagos lo pueda mostrar igual. `fechaPago` dentro de
      // cada elemento puede venir como Timestamp o como texto
      // ("YYYY-MM-DD"): `_leerPagosEmbebidos` maneja ambos casos sin
      // lanzar excepciones.
      pagos: _leerPagosEmbebidos(map['pagos'], documentId),
      idEquipoVinculado: map['idEquipoVinculado'] as String?,
      tipoEquipoVinculado: map['tipoEquipoVinculado'] as String?,
    );
  }

  factory DeudaModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return DeudaModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'idCliente': idCliente,
      'tipo': tipo.name,
      'concepto': concepto,
      'montoTotal': montoTotal,
      'montoAbonado': montoAbonado,
      'fechaEmision': Timestamp.fromDate(fechaEmision),
      'estado': estado,
      'fechaPago': fechaPago != null ? Timestamp.fromDate(fechaPago!) : null,
      'numeroDeuda': numeroDeuda,
      'nota': nota,
      'idEquipoVinculado': idEquipoVinculado,
      'tipoEquipoVinculado': tipoEquipoVinculado,
    };
  }

  DeudaModel copyWith({
    String? id,
    String? idCliente,
    TipoDeuda? tipo,
    String? concepto,
    double? montoTotal,
    double? montoAbonado,
    DateTime? fechaEmision,
    String? estado,
    DateTime? fechaPago,
    bool limpiarFechaPago = false,
    String? numeroDeuda,
    String? nota,
    List<PagoModel>? pagos,
    String? idEquipoVinculado,
    String? tipoEquipoVinculado,
  }) {
    return DeudaModel(
      id: id ?? this.id,
      idCliente: idCliente ?? this.idCliente,
      tipo: tipo ?? this.tipo,
      concepto: concepto ?? this.concepto,
      montoTotal: montoTotal ?? this.montoTotal,
      montoAbonado: montoAbonado ?? this.montoAbonado,
      fechaEmision: fechaEmision ?? this.fechaEmision,
      estado: estado ?? this.estado,
      fechaPago: limpiarFechaPago ? null : (fechaPago ?? this.fechaPago),
      numeroDeuda: numeroDeuda ?? this.numeroDeuda,
      nota: nota ?? this.nota,
      pagos: pagos ?? this.pagos,
      idEquipoVinculado: idEquipoVinculado ?? this.idEquipoVinculado,
      tipoEquipoVinculado: tipoEquipoVinculado ?? this.tipoEquipoVinculado,
    );
  }
}

/// Parsea un posible campo `pagos` embebido como array dentro del propio
/// documento de la deuda (formato: `[{montoAbonado, fechaPago, metodoPago,
/// nota}, ...]`). Devuelve `null` si `valor` no es una lista no vacía, para
/// no confundir "sin pagos embebidos" con "lista vacía".
///
/// Como estos elementos no tienen un documento propio en la colección de
/// nivel superior `pagos`, se les asigna un id sintético (`embebido-...`)
/// que [PagoModel] expone solo para uso interno de la UI: no sirve como ID
/// real de Firestore, así que no se puede usar para editar ni eliminar
/// estos pagos (ver `_HistorialPagos` en finanzas_screen.dart).
List<PagoModel>? _leerPagosEmbebidos(dynamic valor, String idDeuda) {
  if (valor is! List || valor.isEmpty) return null;

  final resultado = <PagoModel>[];
  for (var i = 0; i < valor.length; i++) {
    final item = valor[i];
    if (item is! Map) continue;
    final datos = Map<String, dynamic>.from(item);
    resultado.add(PagoModel(
      id: 'embebido-$idDeuda-$i',
      idDeuda: idDeuda,
      fechaPago: leerFechaFirestore(datos['fechaPago']) ?? DateTime.now(),
      montoAbonado:
          leerMontoFirestore(datos['montoAbonado'] ?? datos['monto']) ?? 0,
      metodoPago: (datos['metodoPago'] ?? datos['medioPago'] ?? '').toString().trim(),
      nota: (datos['nota'] ?? '').toString().trim(),
    ));
  }
  return resultado.isEmpty ? null : resultado;
}
