import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo para productos no seriados: fundas, vidrios templados,
/// cargadores, repuestos y demás insumos del negocio.
class StockEmpresaModel {
  final String id;
  final String nombre;
  final String categoria; // Ej: "Fundas", "Vidrios", "Repuestos", "Accesorios"
  final int cantidad;
  final double costoUnitario;
  final double precioVenta;

  const StockEmpresaModel({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.cantidad,
    required this.costoUnitario,
    required this.precioVenta,
  });

  /// Ganancia unitaria (precioVenta - costoUnitario).
  double get gananciaUnitaria => precioVenta - costoUnitario;

  /// Valor total del stock a costo.
  double get valorTotalCosto => costoUnitario * cantidad;

  /// Valor total del stock a precio de venta.
  double get valorTotalVenta => precioVenta * cantidad;

  /// Indica si el stock está por debajo de un umbral mínimo (por defecto 3).
  bool stockBajo({int umbral = 3}) => cantidad <= umbral;

  factory StockEmpresaModel.fromMap(Map<String, dynamic> map, String documentId) {
    return StockEmpresaModel(
      id: documentId,
      nombre: map['nombre'] ?? '',
      categoria: map['categoria'] ?? '',
      cantidad: (map['cantidad'] ?? 0) as int,
      costoUnitario: (map['costoUnitario'] ?? 0).toDouble(),
      precioVenta: (map['precioVenta'] ?? 0).toDouble(),
    );
  }

  factory StockEmpresaModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return StockEmpresaModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'categoria': categoria,
      'cantidad': cantidad,
      'costoUnitario': costoUnitario,
      'precioVenta': precioVenta,
    };
  }

  StockEmpresaModel copyWith({
    String? id,
    String? nombre,
    String? categoria,
    int? cantidad,
    double? costoUnitario,
    double? precioVenta,
  }) {
    return StockEmpresaModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      categoria: categoria ?? this.categoria,
      cantidad: cantidad ?? this.cantidad,
      costoUnitario: costoUnitario ?? this.costoUnitario,
      precioVenta: precioVenta ?? this.precioVenta,
    );
  }
}
