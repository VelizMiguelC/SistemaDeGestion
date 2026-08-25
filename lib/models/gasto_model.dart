import 'package:cloud_firestore/cloud_firestore.dart';

/// Categoría de un egreso del negocio.
enum CategoriaGasto { alquiler, insumos, servicios, importacion, personal, varios }

extension CategoriaGastoExtension on CategoriaGasto {
  String get label {
    switch (this) {
      case CategoriaGasto.alquiler:
        return 'Alquiler';
      case CategoriaGasto.insumos:
        return 'Local / Insumos';
      case CategoriaGasto.servicios:
        return 'Servicios';
      case CategoriaGasto.importacion:
        return 'Importación / Fletes';
      case CategoriaGasto.personal:
        return 'Personal';
      case CategoriaGasto.varios:
        return 'Varios';
    }
  }

  static CategoriaGasto fromString(String? value) {
    return CategoriaGasto.values.firstWhere(
      (c) => c.name == value,
      orElse: () => CategoriaGasto.varios,
    );
  }
}

/// Moneda en la que está expresado el monto de un gasto.
enum MonedaGasto { usd, ars }

extension MonedaGastoExtension on MonedaGasto {
  String get label {
    switch (this) {
      case MonedaGasto.usd:
        return 'USD';
      case MonedaGasto.ars:
        return 'ARS';
    }
  }

  static MonedaGasto fromString(String? value) {
    return MonedaGasto.values.firstWhere(
      (m) => m.name == value,
      orElse: () => MonedaGasto.ars,
    );
  }
}

/// Medio de pago con el que se abonó un gasto.
enum MedioPago { efectivo, transferencia }

extension MedioPagoExtension on MedioPago {
  String get label {
    switch (this) {
      case MedioPago.efectivo:
        return 'Efectivo';
      case MedioPago.transferencia:
        return 'Transferencia';
    }
  }

  static MedioPago fromString(String? value) {
    return MedioPago.values.firstWhere(
      (m) => m.name == value,
      orElse: () => MedioPago.efectivo,
    );
  }
}

/// Modelo para registrar egresos del negocio (alquiler, insumos, servicios,
/// importación/fletes, personal, varios).
class GastoModel {
  final String id;
  final String descripcion;
  final double monto;
  final MonedaGasto moneda;
  final CategoriaGasto categoria;
  final DateTime fecha;
  final MedioPago medioPago;

  const GastoModel({
    required this.id,
    required this.descripcion,
    required this.monto,
    this.moneda = MonedaGasto.ars,
    required this.categoria,
    required this.fecha,
    required this.medioPago,
  });

  factory GastoModel.fromMap(Map<String, dynamic> map, String documentId) {
    return GastoModel(
      id: documentId,
      descripcion: map['descripcion'] ?? '',
      monto: (map['monto'] ?? 0).toDouble(),
      moneda: MonedaGastoExtension.fromString(map['moneda']),
      categoria: CategoriaGastoExtension.fromString(map['categoria']),
      fecha: map['fecha'] is Timestamp
          ? (map['fecha'] as Timestamp).toDate()
          : DateTime.now(),
      medioPago: MedioPagoExtension.fromString(map['medioPago']),
    );
  }

  factory GastoModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GastoModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'descripcion': descripcion,
      'monto': monto,
      'moneda': moneda.name,
      'categoria': categoria.name,
      'fecha': Timestamp.fromDate(fecha),
      'medioPago': medioPago.name,
    };
  }

  GastoModel copyWith({
    String? id,
    String? descripcion,
    double? monto,
    MonedaGasto? moneda,
    CategoriaGasto? categoria,
    DateTime? fecha,
    MedioPago? medioPago,
  }) {
    return GastoModel(
      id: id ?? this.id,
      descripcion: descripcion ?? this.descripcion,
      monto: monto ?? this.monto,
      moneda: moneda ?? this.moneda,
      categoria: categoria ?? this.categoria,
      fecha: fecha ?? this.fecha,
      medioPago: medioPago ?? this.medioPago,
    );
  }
}
