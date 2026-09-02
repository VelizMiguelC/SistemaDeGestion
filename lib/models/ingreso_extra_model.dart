import 'package:cloud_firestore/cloud_firestore.dart';

import 'gasto_model.dart' show MedioPago, MedioPagoExtension, MonedaGasto, MonedaGastoExtension;

/// Modelo para ingresos del negocio que no vienen de la venta de un equipo
/// (iPhone/Android): reparaciones, arreglos, instalación de accesorios,
/// service técnico, etc. Reutiliza [MonedaGasto] y [MedioPago] de
/// `gasto_model.dart` -son los mismos conceptos, solo que acá suman al
/// balance en vez de restar.
class IngresoExtraModel {
  final String id;
  final String concepto;
  final double monto;
  final MonedaGasto moneda;
  final DateTime fecha;
  final MedioPago medioPago;

  const IngresoExtraModel({
    required this.id,
    required this.concepto,
    required this.monto,
    this.moneda = MonedaGasto.ars,
    required this.fecha,
    required this.medioPago,
  });

  factory IngresoExtraModel.fromMap(Map<String, dynamic> map, String documentId) {
    return IngresoExtraModel(
      id: documentId,
      concepto: (map['concepto'] ?? '').toString(),
      monto: (map['monto'] ?? 0).toDouble(),
      moneda: MonedaGastoExtension.fromString(map['moneda']),
      fecha: map['fecha'] is Timestamp
          ? (map['fecha'] as Timestamp).toDate()
          : DateTime.now(),
      medioPago: MedioPagoExtension.fromString(map['medioPago']),
    );
  }

  factory IngresoExtraModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return IngresoExtraModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'concepto': concepto,
      'monto': monto,
      'moneda': moneda.name,
      'fecha': Timestamp.fromDate(fecha),
      'medioPago': medioPago.name,
    };
  }

  IngresoExtraModel copyWith({
    String? id,
    String? concepto,
    double? monto,
    MonedaGasto? moneda,
    DateTime? fecha,
    MedioPago? medioPago,
  }) {
    return IngresoExtraModel(
      id: id ?? this.id,
      concepto: concepto ?? this.concepto,
      monto: monto ?? this.monto,
      moneda: moneda ?? this.moneda,
      fecha: fecha ?? this.fecha,
      medioPago: medioPago ?? this.medioPago,
    );
  }
}
