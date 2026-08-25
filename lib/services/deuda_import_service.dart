import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_parsing.dart';

/// Resultado de una importación de deudas desde JSON.
class ResultadoImportacionJson {
  final int deudasCreadas;
  final int clientesCreados;
  final int pagosCreados;
  final List<String> avisos;

  const ResultadoImportacionJson({
    required this.deudasCreadas,
    required this.clientesCreados,
    required this.pagosCreados,
    required this.avisos,
  });
}

/// Importa una lista de deudas desde un texto JSON directamente a Firestore
/// (colecciones `clientes` y `deudas`), usando la conexión de Firebase ya
/// activa en la app (no requiere credenciales aparte ni acceso de red
/// externo al dispositivo: corre dentro de la propia app, a diferencia del
/// script Python que sí necesita una clave de servicio).
///
/// Formato esperado (una lista de objetos; también acepta
/// `{"deudas": [...]}`):
/// ```json
/// [
///   {
///     "cliente": "Juan Pérez",        // obligatorio
///     "telefono": "3814445566",       // opcional
///     "tipo": "deudor",               // "deudor" (me deben) o "acreedor" (debo); default "deudor"
///     "concepto": "iPhone 12",        // opcional
///     "montoTotal": 150000,           // obligatorio
///     "montoAbonado": 0,              // opcional, default 0
///     "fechaCreacion": "2026-05-10",  // opcional (ISO-8601), default ahora
///     "estado": "pendiente",          // "pendiente" o "pagado"; si se omite, se calcula solo
///     "fechaPago": "2026-06-01",      // opcional, solo tiene efecto si estado = "pagado"
///     "numeroDeuda": "D-000123",      // opcional
///     "nota": "",                     // opcional
///     "pagos": [                      // opcional: historial de abonos individuales
///       {
///         "montoAbonado": 20000,        // obligatorio dentro de cada pago
///         "fechaPago": "2026-05-20",     // opcional (ISO-8601), default ahora
///         "metodoPago": "efectivo",      // opcional, default "efectivo"
///         "nota": ""                     // opcional
///       }
///     ]
///   }
/// ]
/// ```
/// Si una deuda trae `pagos`, cada uno se guarda como un documento propio
/// en la colección `pagos` (igual que los que se registran a mano desde
/// "Registrar Pago"), y el `montoAbonado`/`estado` de la deuda se calculan
/// solos a partir de la suma de esos pagos (se ignora cualquier
/// `montoAbonado` suelto en ese caso, para que no queden inconsistentes).
///
/// Si ya existe un cliente con el mismo nombre (comparado sin distinguir
/// mayúsculas ni espacios extra), se reutiliza su documento en vez de
/// crear uno duplicado.
Future<ResultadoImportacionJson> importarDeudasDesdeJson(String jsonTexto) async {
  final clientesCol = FirebaseFirestore.instance.collection('clientes');
  final deudasCol = FirebaseFirestore.instance.collection('deudas');
  final pagosCol = FirebaseFirestore.instance.collection('pagos');

  final List<dynamic> filas;
  try {
    final decodificado = jsonDecode(jsonTexto);
    if (decodificado is List) {
      filas = decodificado;
    } else if (decodificado is Map && decodificado['deudas'] is List) {
      filas = decodificado['deudas'] as List;
    } else {
      return const ResultadoImportacionJson(
        deudasCreadas: 0,
        clientesCreados: 0,
        pagosCreados: 0,
        avisos: ['El JSON debe ser una lista de deudas (o un objeto con la clave "deudas").'],
      );
    }
  } catch (e) {
    return ResultadoImportacionJson(
      deudasCreadas: 0,
      clientesCreados: 0,
      pagosCreados: 0,
      avisos: ['JSON inválido: $e'],
    );
  }

  // Cache de clientes existentes por nombre normalizado, para no pegarle a
  // Firestore una vez por fila ni crear duplicados.
  final existentes = await clientesCol.get();
  final clientesPorNombre = <String, String>{
    for (final doc in existentes.docs)
      ((doc.data()['nombre'] ?? '') as String).trim().toLowerCase(): doc.id,
  };

  var deudasCreadas = 0;
  var clientesCreados = 0;
  var pagosCreados = 0;
  final avisos = <String>[];

  for (var i = 0; i < filas.length; i++) {
    final fila = filas[i];
    if (fila is! Map) {
      avisos.add('Fila ${i + 1}: no es un objeto JSON válido, se omite.');
      continue;
    }
    final datos = Map<String, dynamic>.from(fila);

    final nombreCliente = (datos['cliente'] ?? datos['nombreCliente'] ?? '').toString().trim();
    if (nombreCliente.isEmpty) {
      avisos.add('Fila ${i + 1}: falta el campo "cliente", se omite.');
      continue;
    }

    final montoTotal = leerMontoFirestore(datos['montoTotal']);
    if (montoTotal == null) {
      avisos.add('Fila ${i + 1} ($nombreCliente): "montoTotal" inválido o ausente, se omite.');
      continue;
    }

    final claveNombre = nombreCliente.toLowerCase();
    var idCliente = clientesPorNombre[claveNombre];
    if (idCliente == null) {
      final ref = await clientesCol.add({
        'nombre': nombreCliente,
        'telefono': (datos['telefono'] ?? '').toString().trim(),
        'notas': '',
      });
      idCliente = ref.id;
      clientesPorNombre[claveNombre] = idCliente;
      clientesCreados++;
    }

    final tipoTexto = (datos['tipo'] ?? 'deudor').toString().trim().toLowerCase();
    final tipo = tipoTexto == 'acreedor' ? 'acreedor' : 'deudor';

    final fechaCreacionRaw = datos['fechaCreacion'] ?? datos['fecha'];
    final fechaCreacion = fechaCreacionRaw != null
        ? (DateTime.tryParse(fechaCreacionRaw.toString()) ?? DateTime.now())
        : DateTime.now();

    // --- Historial de pagos embebido en esta fila -----------------------
    // Cada entrada se valida por separado; si a una le falta el monto, se
    // avisa y se la omite sin descartar el resto de la deuda.
    //
    // Acepta la clave "pagos" (nombre documentado) y, por las dudas, el
    // alias "abonos". Si la clave viene presente pero con una forma que no
    // es una lista (typo, objeto suelto, string, etc.), se deja un aviso
    // explícito en vez de descartarla en silencio -que es lo que hacía
    // parecer que "no se guardaban los pagos" sin ninguna pista de por qué.
    final pagosRaw = datos['pagos'] ?? datos['abonos'];
    List<dynamic> pagosEntrada;
    if (pagosRaw == null) {
      pagosEntrada = const [];
    } else if (pagosRaw is List) {
      pagosEntrada = pagosRaw;
    } else {
      avisos.add(
        'Fila ${i + 1} ($nombreCliente): "pagos" debe ser una lista de objetos '
        '(se recibió ${pagosRaw.runtimeType}), no se importó ningún pago para esta cuenta.',
      );
      pagosEntrada = const [];
    }

    final pagosParaCrear = <Map<String, dynamic>>[];
    double montoAbonadoDesdesPagos = 0;

    for (var j = 0; j < pagosEntrada.length; j++) {
      final pagoRaw = pagosEntrada[j];
      if (pagoRaw is! Map) {
        avisos.add(
          'Fila ${i + 1} ($nombreCliente): el pago ${j + 1} no es un objeto JSON válido, se omite.',
        );
        continue;
      }
      final pagoDatos = Map<String, dynamic>.from(pagoRaw);
      final montoPagoRaw =
          pagoDatos['montoAbonado'] ?? pagoDatos['monto'] ?? pagoDatos['importe'];
      final montoPago = leerMontoFirestore(montoPagoRaw);
      if (montoPago == null) {
        avisos.add(
          'Fila ${i + 1} ($nombreCliente): el pago ${j + 1} no tiene "montoAbonado" válido '
          '(valor recibido: ${montoPagoRaw ?? "ausente"}), se omite.',
        );
        continue;
      }
      final fechaPagoRawItem = pagoDatos['fechaPago'] ?? pagoDatos['fecha'];
      final fechaPagoItem = fechaPagoRawItem != null
          ? (DateTime.tryParse(fechaPagoRawItem.toString()) ?? DateTime.now())
          : DateTime.now();
      final metodoPagoItem =
          (pagoDatos['metodoPago'] ?? pagoDatos['medioPago'] ?? '').toString().trim();

      montoAbonadoDesdesPagos += montoPago;
      pagosParaCrear.add({
        'montoAbonado': montoPago,
        'fechaPago': Timestamp.fromDate(fechaPagoItem),
        'metodoPago': metodoPagoItem.isEmpty ? 'efectivo' : metodoPagoItem,
        'nota': (pagoDatos['nota'] ?? '').toString().trim(),
      });
    }

    if (pagosEntrada.isNotEmpty && pagosParaCrear.isEmpty) {
      avisos.add(
        'Fila ${i + 1} ($nombreCliente): "pagos" traía ${pagosEntrada.length} elemento(s) '
        'pero ninguno pudo importarse (revisá los avisos anteriores).',
      );
    }

    // Si vinieron pagos individuales, el monto abonado de la deuda se
    // calcula solo a partir de ellos (se ignora un "montoAbonado" suelto,
    // para que no queden dos fuentes de verdad desincronizadas). Si no,
    // se respeta el "montoAbonado" declarado (o 0).
    final montoAbonadoCalculado = pagosParaCrear.isNotEmpty
        ? montoAbonadoDesdesPagos
        : (leerMontoFirestore(datos['montoAbonado']) ?? 0);

    // El estado se respeta si viene explícito en el JSON; si no, se calcula
    // solo comparando el monto abonado contra el total.
    final String estado;
    if (datos['estado'] != null) {
      final estadoTexto = datos['estado'].toString().trim().toLowerCase();
      estado = (estadoTexto == 'pagado' || estadoTexto == 'pagada') ? 'pagado' : 'pendiente';
    } else {
      estado = (montoTotal > 0 && montoAbonadoCalculado >= montoTotal) ? 'pagado' : 'pendiente';
    }

    // Si la cuenta queda "pagado", el monto abonado nunca debe quedar por
    // debajo del total (mismo criterio que DeudaProvider.marcarComoPagado).
    final montoAbonado =
        estado == 'pagado' && montoAbonadoCalculado < montoTotal ? montoTotal : montoAbonadoCalculado;

    DateTime? fechaPago;
    if (estado == 'pagado') {
      final fechaPagoRaw = datos['fechaPago'];
      fechaPago = fechaPagoRaw != null ? DateTime.tryParse(fechaPagoRaw.toString()) : null;
      fechaPago ??= pagosParaCrear.isNotEmpty
          ? pagosParaCrear
              .map((p) => (p['fechaPago'] as Timestamp).toDate())
              .reduce((a, b) => a.isAfter(b) ? a : b)
          : DateTime.now();
    }

    // Se escriben la deuda y sus pagos dentro de un try/catch propio de
    // esta fila: si Firestore rechaza algo (reglas de seguridad, red,
    // etc.), se dejaba abortar TODA la función antes -perdiendo el conteo
    // de todo lo ya importado en filas anteriores y sin dejar claro que
    // los pagos de esta fila puntual no se habían guardado-. Ahora se
    // registra como aviso y se sigue con la fila siguiente.
    try {
      final deudaRef = await deudasCol.add({
        'idCliente': idCliente,
        'tipo': tipo,
        'concepto': (datos['concepto'] ?? '').toString().trim(),
        'montoTotal': montoTotal,
        'montoAbonado': montoAbonado,
        'fechaEmision': Timestamp.fromDate(fechaCreacion),
        'estado': estado,
        'fechaPago': fechaPago != null ? Timestamp.fromDate(fechaPago) : null,
        'numeroDeuda': (datos['numeroDeuda'] ?? '').toString().trim(),
        'nota': (datos['nota'] ?? '').toString().trim(),
      });
      deudasCreadas++;

      for (final pago in pagosParaCrear) {
        try {
          await pagosCol.add({'idDeuda': deudaRef.id, ...pago});
          pagosCreados++;
        } catch (e) {
          avisos.add(
            'Fila ${i + 1} ($nombreCliente): la deuda se creó pero un pago '
            'no se pudo guardar en Firestore ($e).',
          );
        }
      }
    } catch (e) {
      avisos.add('Fila ${i + 1} ($nombreCliente): no se pudo guardar en Firestore ($e).');
    }
  }

  return ResultadoImportacionJson(
    deudasCreadas: deudasCreadas,
    clientesCreados: clientesCreados,
    pagosCreados: pagosCreados,
    avisos: avisos,
  );
}
