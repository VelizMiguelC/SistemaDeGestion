import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_parsing.dart';

/// Modelo de un pago (abono) aplicado a una cuenta ([DeudaModel]).
///
/// Vive en la colección de nivel superior `pagos`, vinculado a su cuenta
/// mediante el campo `idDeuda` (antes era una subcolección
/// `deudas/{id}/pagos`; se movió a colección de nivel superior para
/// coincidir con la estructura de importación desde Excel).
class PagoModel {
  final String id;
  final String idDeuda;
  final DateTime fechaPago;
  final double montoAbonado;
  final String metodoPago;

  /// Nota opcional del abono. No forma parte del esquema de importación
  /// original, pero se conserva para no perder funcionalidad existente.
  final String nota;

  /// Cotización del dólar blue (venta) al momento de cobrar este pago,
  /// guardada solo cuando la cuenta corresponde a una venta financiada
  /// (`DeudaModel.esVentaFinanciada`). `null` en el resto de los pagos,
  /// donde no hace falta convertir a USD.
  ///
  /// Es la que usa `reportes_screen.dart` para convertir el monto (en
  /// pesos) a su equivalente en USD al reconocer la ganancia -con la
  /// cotización del día en que efectivamente se cobró, no la de hoy-, así
  /// la devaluación del peso mientras la cuenta está en curso no distorsiona
  /// el balance.
  final double? tasaBlue;

  const PagoModel({
    required this.id,
    required this.idDeuda,
    required this.fechaPago,
    required this.montoAbonado,
    this.metodoPago = '',
    this.nota = '',
    this.tasaBlue,
  });

  factory PagoModel.fromMap(Map<String, dynamic> map, String documentId) {
    return PagoModel(
      id: documentId,
      idDeuda: (map['idDeuda'] ?? '').toString(),
      fechaPago: leerFechaFirestore(map['fechaPago']) ?? DateTime.now(),
      montoAbonado: leerMontoFirestore(map['montoAbonado']) ?? 0,
      metodoPago: (map['metodoPago'] ?? '').toString(),
      nota: (map['nota'] ?? '').toString(),
      tasaBlue: (map['tasaBlue'] as num?)?.toDouble(),
    );
  }

  factory PagoModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PagoModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'idDeuda': idDeuda,
      'fechaPago': Timestamp.fromDate(fechaPago),
      'montoAbonado': montoAbonado,
      'metodoPago': metodoPago,
      'nota': nota,
      'tasaBlue': tasaBlue,
    };
  }

  PagoModel copyWith({
    String? id,
    String? idDeuda,
    DateTime? fechaPago,
    double? montoAbonado,
    String? metodoPago,
    String? nota,
    double? tasaBlue,
  }) {
    return PagoModel(
      id: id ?? this.id,
      idDeuda: idDeuda ?? this.idDeuda,
      fechaPago: fechaPago ?? this.fechaPago,
      montoAbonado: montoAbonado ?? this.montoAbonado,
      metodoPago: metodoPago ?? this.metodoPago,
      nota: nota ?? this.nota,
      tasaBlue: tasaBlue ?? this.tasaBlue,
    );
  }
}
