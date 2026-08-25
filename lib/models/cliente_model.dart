import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de un cliente (deudor o acreedor de una o más cuentas).
///
/// Vive en la colección de nivel superior `clientes`. Las cuentas
/// ([DeudaModel]) y los pagos ([PagoModel]) referencian al cliente por su
/// `id` de documento (campo `idCliente` en `deudas`).
class ClienteModel {
  final String id;
  final String nombre;
  final String telefono;
  final String notas;

  const ClienteModel({
    required this.id,
    required this.nombre,
    this.telefono = '',
    this.notas = '',
  });

  factory ClienteModel.fromMap(Map<String, dynamic> map, String documentId) {
    return ClienteModel(
      id: documentId,
      nombre: (map['nombre'] ?? '').toString(),
      // Por las dudas: si el teléfono quedó guardado como número en vez de
      // texto (típico si alguien lo tipeó a mano en la consola de
      // Firebase), `.toString()` evita un TypeError al asignarlo acá.
      telefono: (map['telefono'] ?? '').toString(),
      notas: (map['notas'] ?? '').toString(),
    );
  }

  factory ClienteModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ClienteModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'telefono': telefono,
      'notas': notas,
    };
  }

  ClienteModel copyWith({
    String? id,
    String? nombre,
    String? telefono,
    String? notas,
  }) {
    return ClienteModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      notas: notas ?? this.notas,
    );
  }
}
