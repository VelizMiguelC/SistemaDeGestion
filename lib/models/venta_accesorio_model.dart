import 'package:cloud_firestore/cloud_firestore.dart';

/// Registro de una venta de un producto de Stock de Empresa (fundas,
/// vidrios, repuestos, etc.).
///
/// A diferencia de simplemente restar del contador de "Cantidad en stock"
/// -que no distingue una venta real de una baja por rotura/pérdida, ni
/// guarda cuándo pasó-, esto queda como un evento fechado que
/// `reportes_screen.dart` puede sumar por período.
///
/// El costo y precio de venta quedan "congelados" acá al momento de la
/// venta (no se recalculan si después cambiás el precio del producto en
/// Stock de Empresa), para que el balance de un mes que ya pasó no cambie
/// solo porque actualizaste una lista de precios.
///
/// Igual que en Stock de Empresa, `costoUnitario`/`precioVenta` están en
/// pesos (no en USD como iPhones/Android) — Reportes los convierte con la
/// cotización del dólar blue, igual que hace con gastos y otros ingresos.
class VentaAccesorioModel {
  final String id;
  final String itemId;
  final String nombre;
  final int cantidad;
  final double costoUnitario;
  final double precioVenta;
  final DateTime fecha;

  const VentaAccesorioModel({
    required this.id,
    required this.itemId,
    required this.nombre,
    required this.cantidad,
    required this.costoUnitario,
    required this.precioVenta,
    required this.fecha,
  });

  double get ingresoTotal => cantidad * precioVenta;
  double get costoTotal => cantidad * costoUnitario;
  double get gananciaTotal => ingresoTotal - costoTotal;

  factory VentaAccesorioModel.fromMap(Map<String, dynamic> map, String documentId) {
    return VentaAccesorioModel(
      id: documentId,
      itemId: (map['itemId'] ?? '').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      cantidad: (map['cantidad'] ?? 0) as int,
      costoUnitario: (map['costoUnitario'] ?? 0).toDouble(),
      precioVenta: (map['precioVenta'] ?? 0).toDouble(),
      fecha: map['fecha'] is Timestamp ? (map['fecha'] as Timestamp).toDate() : DateTime.now(),
    );
  }

  factory VentaAccesorioModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return VentaAccesorioModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'nombre': nombre,
      'cantidad': cantidad,
      'costoUnitario': costoUnitario,
      'precioVenta': precioVenta,
      'fecha': Timestamp.fromDate(fecha),
    };
  }
}
