import 'package:cloud_firestore/cloud_firestore.dart';

/// Convierte un valor leído de un documento de Firestore a [DateTime],
/// aceptando tanto un [Timestamp] nativo (lo normal, cuando el documento se
/// crea desde la propia app) como una fecha en texto ISO-8601
/// (ej. `"2026-06-01"`), que es lo que puede terminar guardado si un
/// documento se cargó a mano en la consola de Firebase o vía una
/// herramienta externa que no convirtió el valor a Timestamp.
///
/// Antes se usaba un cast directo (`valor as Timestamp?`), que lanzaba una
/// excepción en tiempo de ejecución apenas el valor no era exactamente un
/// Timestamp, en vez de degradar con gracia. Devuelve `null` si el valor es
/// `null`, vacío, o no se puede interpretar como fecha de ninguna forma.
DateTime? leerFechaFirestore(dynamic valor) {
  if (valor == null) return null;
  if (valor is Timestamp) return valor.toDate();
  if (valor is DateTime) return valor;
  if (valor is String) {
    final texto = valor.trim();
    if (texto.isEmpty) return null;
    return DateTime.tryParse(texto);
  }
  return null;
}

/// Convierte un valor de monto leído de Firestore (número, o texto con
/// formatos como "20000", "20.000", "20,000.50", "$ 20.000" o " 20000 ")
/// a `double`. Devuelve `null` si no se puede interpretar como número.
double? leerMontoFirestore(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  var texto = valor.toString().trim();
  if (texto.isEmpty) return null;

  // Saca símbolos de moneda, espacios y cualquier otro carácter que no sea
  // dígito, coma, punto o signo menos.
  texto = texto.replaceAll(RegExp(r'[^\d,.\-]'), '');
  if (texto.isEmpty) return null;

  final tieneComa = texto.contains(',');
  final tienePunto = texto.contains('.');
  if (tieneComa && tienePunto) {
    // Trae los dos separadores: el que aparece último es el decimal.
    if (texto.lastIndexOf(',') > texto.lastIndexOf('.')) {
      // Coma decimal, punto de miles (es-AR): "1.234,56" -> "1234.56"
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      // Punto decimal, coma de miles (en-US): "1,234.56" -> "1234.56"
      texto = texto.replaceAll(',', '');
    }
  } else if (tieneComa) {
    // Solo coma: puede ser decimal ("20000,50") o de miles ("20,000").
    final ultimoGrupo = texto.split(',').last;
    texto = ultimoGrupo.length == 2 ? texto.replaceAll(',', '.') : texto.replaceAll(',', '');
  }

  return num.tryParse(texto)?.toDouble();
}
