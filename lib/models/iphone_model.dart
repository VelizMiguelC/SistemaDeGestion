import 'package:cloud_firestore/cloud_firestore.dart';

/// Estado físico/comercial del equipo.
enum EstadoIPhone { nuevo, usado }

extension EstadoIPhoneExtension on EstadoIPhone {
  String get label {
    switch (this) {
      case EstadoIPhone.nuevo:
        return 'Nuevo';
      case EstadoIPhone.usado:
        return 'Usado';
    }
  }

  static EstadoIPhone fromString(String value) {
    return EstadoIPhone.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EstadoIPhone.usado,
    );
  }
}

/// Resultado del cálculo de garantía restante de un equipo vendido.
///
/// El desglose de meses/días es aproximado (usa meses de 30 días) y solo
/// tiene sentido cuando el equipo ya fue vendido (`fechaVenta` no nulo).
class TiempoGarantiaRestante {
  final int meses;
  final int dias;
  final bool vencida;

  const TiempoGarantiaRestante({
    required this.meses,
    required this.dias,
    required this.vencida,
  });

  /// Texto legible listo para mostrar en la UI.
  String get descripcion {
    if (vencida) return 'Garantía vencida';
    if (meses > 0) {
      final sufijoMeses = meses == 1 ? 'mes' : 'meses';
      if (dias > 0) {
        final sufijoDias = dias == 1 ? 'día' : 'días';
        return '$meses $sufijoMeses y $dias $sufijoDias restantes';
      }
      return '$meses $sufijoMeses restantes';
    }
    final sufijoDias = dias == 1 ? 'día' : 'días';
    return '$dias $sufijoDias restantes';
  }
}

/// Modelo de un iPhone individual (producto serializado por IMEI).
class IPhoneModel {
  final String id;
  final String imei;
  final String modelo; // Ej: "iPhone 13 Pro"
  final String capacidad; // Ej: "128GB"
  final String color;
  final int bateria; // Porcentaje de salud de batería (0-100)
  final EstadoIPhone estado;

  /// Costo de adquisición, en dólares (USD). Obligatorio.
  final double costo;

  /// Precio de venta al público, en dólares (USD). Opcional mientras el
  /// equipo está en stock: se puede dejar sin definir al cargarlo y recién
  /// queda fijado (o se ajusta) en el momento de marcarlo como Vendido.
  final double? precioVenta;

  final bool esCompartido; // Si el equipo es de inversión compartida
  final String? nombreSocio; // Nombre del socio, si esCompartido == true
  final double? porcentajeSocio; // % de ganancia que le corresponde al socio (0-100)
  final bool vendido;
  final int mesesGarantia; // Meses de garantía ofrecidos (ej: 3, 6, 12)
  final DateTime? fechaVenta; // Fecha en la que se vendió el equipo
  final String? telefonoCliente; // Contacto del cliente que lo compró

  const IPhoneModel({
    required this.id,
    required this.imei,
    required this.modelo,
    required this.capacidad,
    required this.color,
    required this.bateria,
    required this.estado,
    required this.costo,
    this.precioVenta,
    this.esCompartido = false,
    this.nombreSocio,
    this.porcentajeSocio,
    this.vendido = false,
    this.mesesGarantia = 0,
    this.fechaVenta,
    this.telefonoCliente,
  });

  /// Ganancia (precioVenta - costo), en USD. `null` si todavía no se definió
  /// un precio de venta (equipo aún no vendido / sin precio estimado).
  double? get ganancia => precioVenta == null ? null : precioVenta! - costo;

  /// Parte de la ganancia que corresponde al socio (si aplica), en USD.
  /// `null` si todavía no hay `ganancia` calculable.
  double? get gananciaSocio {
    if (!esCompartido || porcentajeSocio == null) return 0;
    final g = ganancia;
    if (g == null) return null;
    return g * (porcentajeSocio! / 100);
  }

  /// Ganancia neta que queda para el dueño del negocio (descontado el socio,
  /// si corresponde), en USD. `null` si todavía no hay `ganancia` calculable.
  double? get gananciaPropia {
    final g = ganancia;
    if (g == null) return null;
    return g - (gananciaSocio ?? 0);
  }

  /// Tiempo de garantía restante a partir de `fechaVenta` + `mesesGarantia`.
  ///
  /// Devuelve `null` si el equipo todavía no fue vendido (sin `fechaVenta`).
  TiempoGarantiaRestante? get tiempoGarantiaRestante {
    if (fechaVenta == null) return null;

    final fecha = fechaVenta!;
    final fechaFinGarantia = DateTime(fecha.year, fecha.month + mesesGarantia, fecha.day);
    final restante = fechaFinGarantia.difference(DateTime.now());

    if (restante.isNegative) {
      return const TiempoGarantiaRestante(meses: 0, dias: 0, vencida: true);
    }

    final diasTotales = restante.inDays;
    return TiempoGarantiaRestante(
      meses: diasTotales ~/ 30,
      dias: diasTotales % 30,
      vencida: false,
    );
  }

  factory IPhoneModel.fromMap(Map<String, dynamic> map, String documentId) {
    return IPhoneModel(
      id: documentId,
      imei: map['imei'] ?? '',
      modelo: map['modelo'] ?? '',
      capacidad: map['capacidad'] ?? '',
      color: map['color'] ?? '',
      bateria: (map['bateria'] ?? 100) as int,
      estado: EstadoIPhoneExtension.fromString(map['estado'] ?? 'usado'),
      costo: (map['costo'] ?? 0).toDouble(),
      precioVenta: map['precioVenta'] != null ? (map['precioVenta'] as num).toDouble() : null,
      esCompartido: map['esCompartido'] ?? false,
      nombreSocio: map['nombreSocio'],
      porcentajeSocio: map['porcentajeSocio'] != null
          ? (map['porcentajeSocio'] as num).toDouble()
          : null,
      vendido: map['vendido'] ?? false,
      mesesGarantia: (map['mesesGarantia'] ?? 0) as int,
      fechaVenta: map['fechaVenta'] is Timestamp
          ? (map['fechaVenta'] as Timestamp).toDate()
          : null,
      telefonoCliente: map['telefonoCliente'],
    );
  }

  factory IPhoneModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return IPhoneModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'imei': imei,
      'modelo': modelo,
      'capacidad': capacidad,
      'color': color,
      'bateria': bateria,
      'estado': estado.name,
      'costo': costo,
      'precioVenta': precioVenta,
      'esCompartido': esCompartido,
      'nombreSocio': nombreSocio,
      'porcentajeSocio': porcentajeSocio,
      'vendido': vendido,
      'mesesGarantia': mesesGarantia,
      'fechaVenta': fechaVenta != null ? Timestamp.fromDate(fechaVenta!) : null,
      'telefonoCliente': telefonoCliente,
    };
  }

  IPhoneModel copyWith({
    String? id,
    String? imei,
    String? modelo,
    String? capacidad,
    String? color,
    int? bateria,
    EstadoIPhone? estado,
    double? costo,
    double? precioVenta,
    bool? esCompartido,
    String? nombreSocio,
    double? porcentajeSocio,
    bool? vendido,
    int? mesesGarantia,
    DateTime? fechaVenta,
    String? telefonoCliente,
  }) {
    return IPhoneModel(
      id: id ?? this.id,
      imei: imei ?? this.imei,
      modelo: modelo ?? this.modelo,
      capacidad: capacidad ?? this.capacidad,
      color: color ?? this.color,
      bateria: bateria ?? this.bateria,
      estado: estado ?? this.estado,
      costo: costo ?? this.costo,
      precioVenta: precioVenta ?? this.precioVenta,
      esCompartido: esCompartido ?? this.esCompartido,
      nombreSocio: nombreSocio ?? this.nombreSocio,
      porcentajeSocio: porcentajeSocio ?? this.porcentajeSocio,
      vendido: vendido ?? this.vendido,
      mesesGarantia: mesesGarantia ?? this.mesesGarantia,
      fechaVenta: fechaVenta ?? this.fechaVenta,
      telefonoCliente: telefonoCliente ?? this.telefonoCliente,
    );
  }
}
