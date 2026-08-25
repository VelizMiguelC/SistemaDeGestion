import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show DeudaProvider, ClienteProvider, PagoProvider, AppDrawer;
import '../models/cliente_model.dart';
import '../models/deuda_model.dart';
import '../models/pago_model.dart';
import '../services/deuda_import_service.dart';

final _formatoMoneda = NumberFormat.currency(locale: 'es_AR', symbol: '\$', decimalDigits: 0);
final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Color de marca de WhatsApp, usado solo como acento visual del botón de
/// acceso directo (no dependemos de ningún paquete de íconos de marca).
const _colorWhatsApp = Color(0xFF25D366);

/// Medio de pago de un abono. Se guarda como String en el campo
/// `metodoPago` de cada documento de la colección `pagos`. Puede venir de la
/// app (valores en minúscula, ej. "efectivo") o de la importación masiva
/// desde Excel (valores capitalizados, ej. "Efectivo"), por eso la
/// comparación en [MedioPagoExtension.fromString] ignora mayúsculas.
enum MedioPago { transferencia, efectivo }

extension MedioPagoExtension on MedioPago {
  String get label {
    switch (this) {
      case MedioPago.transferencia:
        return 'Transferencia';
      case MedioPago.efectivo:
        return 'Efectivo';
    }
  }

  IconData get icon {
    switch (this) {
      case MedioPago.transferencia:
        return Icons.account_balance;
      case MedioPago.efectivo:
        return Icons.payments;
    }
  }

  Color get color {
    switch (this) {
      case MedioPago.transferencia:
        return Colors.blue;
      case MedioPago.efectivo:
        return Colors.green;
    }
  }

  static MedioPago fromString(String? value) {
    if (value == null || value.trim().isEmpty) return MedioPago.efectivo;
    final normalizado = value.trim().toLowerCase();
    return MedioPago.values.firstWhere(
      (m) => m.name.toLowerCase() == normalizado || m.label.toLowerCase() == normalizado,
      orElse: () => MedioPago.efectivo,
    );
  }
}

Future<void> _llamar(BuildContext context, String telefono) async {
  final uri = Uri(scheme: 'tel', path: telefono);
  final ok = await launchUrl(uri, webOnlyWindowName: '_self');
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo iniciar la llamada')),
    );
  }
}

/// Normaliza un número argentino al formato internacional que espera
/// WhatsApp (wa.me): solo dígitos, con el código de país '549' antepuesto
/// si el número no lo tiene ya.
///
/// Casos que cubre:
/// - Ya viene completo ("549381XXXXXXX") -> se deja igual.
/// - Tiene código de país pero sin el '9' de celular ("54381XXXXXXX")
///   -> se le inserta el 9 ("549381XXXXXXX").
/// - Número local, con o sin el 0 de larga distancia ("0381XXXXXXX" o
///   "381XXXXXXX") -> se le saca el 0 (si está) y se antepone "549".
String _normalizarTelefonoArgentina(String telefono) {
  var digitos = telefono.replaceAll(RegExp(r'[^\d]'), '');
  if (digitos.startsWith('00')) digitos = digitos.substring(2);
  if (digitos.startsWith('549')) return digitos;
  if (digitos.startsWith('54')) return '549${digitos.substring(2)}';
  if (digitos.startsWith('0')) digitos = digitos.substring(1);
  return '549$digitos';
}

/// Abre WhatsApp con el número indicado. Si se pasa [mensaje], lo deja
/// precargado en el campo de texto del chat (el usuario lo revisa y lo
/// envía a mano; no se manda nada automáticamente).
///
/// Usa el enlace universal `https://wa.me/...` (nunca el esquema
/// `whatsapp://send`, que iOS/Safari bloquea dentro de una PWA instalada
/// en el inicio). El parámetro `webOnlyWindowName: '_self'` es clave para
/// que funcione como PWA en iOS: en modo standalone, Safari ignora los
/// `window.open()` a una pestaña nueva (que es lo que hace
/// `LaunchMode.externalApplication` en la web por defecto) y el botón
/// queda "mudo". Navegando en la misma ventana, Safari sí reconoce el
/// enlace a wa.me y dispara la apertura de la app de WhatsApp.
Future<void> _abrirWhatsApp(BuildContext context, String telefono, {String mensaje = ''}) async {
  final numeroLimpio = _normalizarTelefonoArgentina(telefono);
  final uri = Uri.parse('https://wa.me/$numeroLimpio').replace(
    queryParameters: mensaje.isEmpty ? null : {'text': mensaje},
  );
  final ok = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_self',
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir WhatsApp')),
    );
  }
}

/// Arma el resumen completo de una cuenta para mandar por WhatsApp: total,
/// el detalle de cada pago (fecha + monto), total abonado y saldo
/// pendiente. Adaptado según si es una cuenta por cobrar ("me deben") o
/// por pagar ("debo"). [pagos] puede venir vacío (por ejemplo, si falló la
/// consulta a Firestore): el mensaje igual sale, solo que sin el detalle
/// de abonos.
String _mensajeResumenCuenta(DeudaModel deuda, ClienteModel? cliente, List<PagoModel> pagos) {
  final esDeudor = deuda.tipo == TipoDeuda.deudor; // true = me deben

  final nombre = cliente?.nombre.trim();
  final saludo = (nombre != null && nombre.isNotEmpty) ? 'Hola $nombre!' : 'Hola!';
  final concepto = deuda.concepto.trim();
  final detalleConcepto = concepto.isNotEmpty ? ' ($concepto)' : '';
  final numero = deuda.numeroDeuda.trim();
  final detalleNumero = numero.isNotEmpty ? ' - cuenta #$numero' : '';

  final ordenados = [...pagos]..sort((a, b) => a.fechaPago.compareTo(b.fechaPago));

  final buffer = StringBuffer()
    ..writeln('$saludo Te paso el resumen de tu cuenta$detalleConcepto$detalleNumero:')
    ..writeln()
    ..writeln('Total: ${_formatoMoneda.format(deuda.montoTotal)}');

  if (ordenados.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(esDeudor ? 'Pagos que hiciste:' : 'Pagos que te hice:');
    for (final pago in ordenados) {
      buffer.writeln(
        '• ${_formatoFecha.format(pago.fechaPago)}: ${_formatoMoneda.format(pago.montoAbonado)}',
      );
    }
  }

  buffer
    ..writeln()
    ..writeln('Total abonado: ${_formatoMoneda.format(deuda.montoAbonado)}')
    ..writeln('Saldo pendiente: ${_formatoMoneda.format(deuda.saldoPendiente)}');

  if (deuda.estaSaldada) {
    buffer
      ..writeln()
      ..writeln('¡Cuenta saldada, muchas gracias!');
  } else if (esDeudor) {
    buffer
      ..writeln()
      ..writeln('Cualquier duda me avisás. ¡Gracias!');
  }

  return buffer.toString().trim();
}

/// -----------------------------------------------------------------------
/// PANTALLA: FINANZAS (deudores y acreedores)
/// -----------------------------------------------------------------------

class FinanzasScreen extends StatefulWidget {
  const FinanzasScreen({super.key});

  @override
  State<FinanzasScreen> createState() => _FinanzasScreenState();
}

class _FinanzasScreenState extends State<FinanzasScreen> with TickerProviderStateMixin {
  late final TabController _tabController;
  late final TabController _estadoTabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    // Subpestañas Pendientes / Historial, anidadas dentro de cada tab
    // Me deben / Debo.
    _estadoTabController = TabController(length: 2, vsync: this);
    _estadoTabController.addListener(() {
      if (!_estadoTabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _estadoTabController.dispose();
    super.dispose();
  }

  TipoDeuda get _tipoActual =>
      _tabController.index == 0 ? TipoDeuda.deudor : TipoDeuda.acreedor;

  void _abrirFormularioNuevaCuenta() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _DeudaFormSheet(tipoInicial: _tipoActual),
    );
  }

  void _abrirFormularioEditarCuenta(DeudaModel deuda) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _DeudaFormSheet(tipoInicial: deuda.tipo, deuda: deuda),
    );
  }

  void _abrirImportarJson() {
    showDialog(
      context: context,
      builder: (context) => const _ImportarJsonDialog(),
    );
  }

  Future<void> _eliminarCuenta(DeudaModel deuda, ClienteModel? cliente) async {
    final provider = context.read<DeudaProvider>();
    final nombre = cliente?.nombre ?? '(cliente desconocido)';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Text(
          '¿Eliminar la cuenta de "$nombre"'
          '${deuda.numeroDeuda.isNotEmpty ? ' (#${deuda.numeroDeuda})' : ''}? '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await provider.eliminar(deuda.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuenta eliminada')),
        );
      }
    }
  }

  Future<void> _marcarComoPagado(DeudaModel deuda, ClienteModel? cliente) async {
    final provider = context.read<DeudaProvider>();
    final nombre = cliente?.nombre ?? '(cliente desconocido)';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como pagado'),
        content: Text(
          deuda.saldoPendiente > 0
              ? '¿Marcar la cuenta de "$nombre" como pagada? Se registrará un '
                  'pago por el saldo restante (${_formatoMoneda.format(deuda.saldoPendiente)}) '
                  'y quedará saldada por completo.'
              : '¿Marcar la cuenta de "$nombre" como pagada?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Marcar como pagado'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await provider.marcarComoPagado(deuda);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cuenta marcada como pagada')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al marcar como pagada: $e')),
          );
        }
      }
    }
  }

  Future<void> _reabrirCuenta(DeudaModel deuda) async {
    final provider = context.read<DeudaProvider>();
    try {
      await provider.reabrirCuenta(deuda.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuenta reabierta como pendiente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al reabrir la cuenta: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deudaProvider = context.watch<DeudaProvider>();
    final clienteProvider = context.watch<ClienteProvider>();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Finanzas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Importar deudas desde JSON',
            onPressed: _abrirImportarJson,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.arrow_downward), text: 'Me deben'),
            Tab(icon: Icon(Icons.arrow_upward), text: 'Debo'),
          ],
        ),
      ),
      body: StreamBuilder<List<ClienteModel>>(
        stream: clienteProvider.stream,
        builder: (context, clientesSnap) {
          final clientesPorId = <String, ClienteModel>{
            for (final c in clientesSnap.data ?? const <ClienteModel>[]) c.id: c,
          };

          return StreamBuilder<List<DeudaModel>>(
            stream: deudaProvider.stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error al cargar las cuentas: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final todas = snapshot.data!;
              final totalPorCobrar = todas
                  .where((d) => d.tipo == TipoDeuda.deudor)
                  .fold<double>(0, (acumulado, d) => acumulado + d.saldoPendiente);
              final totalPorPagar = todas
                  .where((d) => d.tipo == TipoDeuda.acreedor)
                  .fold<double>(0, (acumulado, d) => acumulado + d.saldoPendiente);

              final delTipo = todas.where((d) => d.tipo == _tipoActual).toList();
              final pendientes = delTipo.where((d) => !d.pagada).toList()
                ..sort((a, b) => b.fechaEmision.compareTo(a.fechaEmision));
              final pagadas = delTipo.where((d) => d.pagada).toList()
                ..sort((a, b) {
                  final fa = a.fechaPago ?? a.fechaEmision;
                  final fb = b.fechaPago ?? b.fechaEmision;
                  return fb.compareTo(fa);
                });
              final totalPendientes = pendientes.fold<double>(
                0,
                (acumulado, d) => acumulado + d.saldoPendiente,
              );

              return Column(
                children: [
                  _ResumenBanner(
                    totalPorCobrar: totalPorCobrar,
                    totalPorPagar: totalPorPagar,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: TabBar(
                      controller: _estadoTabController,
                      labelColor: Theme.of(context).colorScheme.primary,
                      tabs: const [
                        Tab(text: 'Pendientes'),
                        Tab(text: 'Historial'),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      controller: _estadoTabController,
                      children: [
                        _ListaCuentas(
                          deudas: pendientes,
                          clientesPorId: clientesPorId,
                          totalAlPie: totalPendientes,
                          mensajeVacio: 'No hay cuentas pendientes',
                          onEditar: _abrirFormularioEditarCuenta,
                          onEliminar: (d, c) => _eliminarCuenta(d, c),
                          onMarcarPagado: (d, c) => _marcarComoPagado(d, c),
                        ),
                        _ListaCuentas(
                          deudas: pagadas,
                          clientesPorId: clientesPorId,
                          totalAlPie: null,
                          mensajeVacio: 'Todavía no hay cuentas saldadas',
                          onEditar: _abrirFormularioEditarCuenta,
                          onEliminar: (d, c) => _eliminarCuenta(d, c),
                          onReabrir: _reabrirCuenta,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormularioNuevaCuenta,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

/// Lista de cuentas de una subpestaña (Pendientes o Historial), con total
/// acumulado opcional al pie.
class _ListaCuentas extends StatelessWidget {
  final List<DeudaModel> deudas;
  final Map<String, ClienteModel> clientesPorId;
  final double? totalAlPie;
  final String mensajeVacio;
  final void Function(DeudaModel deuda) onEditar;
  final void Function(DeudaModel deuda, ClienteModel? cliente) onEliminar;
  final void Function(DeudaModel deuda, ClienteModel? cliente)? onMarcarPagado;
  final void Function(DeudaModel deuda)? onReabrir;

  const _ListaCuentas({
    required this.deudas,
    required this.clientesPorId,
    required this.totalAlPie,
    required this.mensajeVacio,
    required this.onEditar,
    required this.onEliminar,
    this.onMarcarPagado,
    this.onReabrir,
  });

  @override
  Widget build(BuildContext context) {
    if (deudas.isEmpty) {
      return Center(child: Text(mensajeVacio));
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: deudas.length,
            itemBuilder: (context, i) {
              final deuda = deudas[i];
              final cliente = clientesPorId[deuda.idCliente];
              return _DeudaCard(
                deuda: deuda,
                cliente: cliente,
                onEditar: () => onEditar(deuda),
                onEliminar: () => onEliminar(deuda, cliente),
                onMarcarPagado:
                    onMarcarPagado == null ? null : () => onMarcarPagado!(deuda, cliente),
                onReabrir: onReabrir == null ? null : () => onReabrir!(deuda),
              );
            },
          ),
        ),
        if (totalAlPie != null) _TotalFooter(total: totalAlPie!),
      ],
    );
  }
}

/// Barra fija al pie de la pestaña "Pendientes" con el total acumulado.
class _TotalFooter extends StatelessWidget {
  final double total;
  const _TotalFooter({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Total pendiente', style: theme.textTheme.titleSmall),
          Text(
            _formatoMoneda.format(total),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// BANNER DE RESUMEN — contadores de saldo destacados
/// -----------------------------------------------------------------------

class _ResumenBanner extends StatelessWidget {
  final double totalPorCobrar;
  final double totalPorPagar;

  const _ResumenBanner({required this.totalPorCobrar, required this.totalPorPagar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _ResumenStatCard(
              icon: Icons.arrow_downward,
              color: Colors.green,
              titulo: 'Por cobrar',
              monto: totalPorCobrar,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ResumenStatCard(
              icon: Icons.arrow_upward,
              color: Colors.red,
              titulo: 'Por pagar',
              monto: totalPorPagar,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumenStatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titulo;
  final double monto;

  const _ResumenStatCard({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.monto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _formatoMoneda.format(monto),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// TARJETA DE CUENTA (deudor o acreedor)
/// -----------------------------------------------------------------------

class _DeudaCard extends StatelessWidget {
  final DeudaModel deuda;
  final ClienteModel? cliente;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  /// No nulo solo en la pestaña "Pendientes": marca la cuenta como pagada.
  final VoidCallback? onMarcarPagado;

  /// No nulo solo en la pestaña "Historial": revierte una cuenta marcada
  /// como pagada por error.
  final VoidCallback? onReabrir;

  const _DeudaCard({
    required this.deuda,
    required this.cliente,
    required this.onEditar,
    required this.onEliminar,
    this.onMarcarPagado,
    this.onReabrir,
  });

  void _abrirDialogoPago(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _RegistrarPagoDialog(deuda: deuda),
    );
  }

  /// Trae el historial de pagos de esta cuenta (colección `pagos` + los
  /// que hubiera embebidos en el propio documento) y recién con eso arma y
  /// abre el mensaje de WhatsApp con el resumen completo. Se hace la
  /// consulta acá -en vez de depender del historial ya cargado- porque el
  /// botón está visible aunque la tarjeta esté colapsada (sin el
  /// `_HistorialPagos` montado).
  Future<void> _recordarPorWhatsApp(BuildContext context, String telefono) async {
    var pagos = <PagoModel>[];
    try {
      pagos = await context.read<PagoProvider>().obtenerPorDeuda(deuda.id);
    } catch (_) {
      // Si falla la consulta, se manda igual el mensaje sin el detalle de
      // pagos (mejor un resumen incompleto que no mandar nada).
    }
    final todosLosPagos = [...?deuda.pagos, ...pagos];
    if (!context.mounted) return;
    await _abrirWhatsApp(
      context,
      telefono,
      mensaje: _mensajeResumenCuenta(deuda, cliente, todosLosPagos),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = deuda.tipo == TipoDeuda.deudor ? Colors.green : Colors.red;
    final telefono = (cliente?.telefono ?? '').trim();
    final nombreCliente = cliente?.nombre.trim().isNotEmpty == true
        ? cliente!.nombre.trim()
        : '(cliente no encontrado)';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: color),
            Expanded(
              child: ExpansionTile(
                tilePadding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
                childrenPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(
                    deuda.tipo == TipoDeuda.deudor ? Icons.arrow_downward : Icons.arrow_upward,
                    color: color,
                  ),
                ),
                title: Row(
                  children: [
                    if (deuda.numeroDeuda.isNotEmpty) ...[
                      _NumeroBadge(numero: deuda.numeroDeuda),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        nombreCliente,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${deuda.concepto.isNotEmpty ? '${deuda.concepto} · ' : ''}'
                      '${_formatoFecha.format(deuda.fechaEmision)}'
                      '${deuda.estaSaldada ? ' · Saldada' : ''}',
                    ),
                    if (telefono.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.phone, size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(telefono, style: theme.textTheme.bodySmall),
                            ),
                            IconButton(
                              icon: const Icon(Icons.call, size: 18),
                              tooltip: 'Llamar',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              padding: EdgeInsets.zero,
                              onPressed: () => _llamar(context, telefono),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chat_bubble, size: 16, color: _colorWhatsApp),
                              tooltip: 'Enviar resumen de cuenta por WhatsApp',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              padding: EdgeInsets.zero,
                              onPressed: () => _recordarPorWhatsApp(context, telefono),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatoMoneda.format(deuda.saldoPendiente),
                          style: TextStyle(fontWeight: FontWeight.w700, color: color),
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (accion) {
                        if (accion == 'editar') onEditar();
                        if (accion == 'eliminar') onEliminar();
                        if (accion == 'reabrir') onReabrir?.call();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'editar',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Editar'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (onReabrir != null)
                          const PopupMenuItem(
                            value: 'reabrir',
                            child: ListTile(
                              leading: Icon(Icons.replay_outlined),
                              title: Text('Reabrir (marcar pendiente)'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        PopupMenuItem(
                          value: 'eliminar',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                            title: Text('Eliminar', style: TextStyle(color: theme.colorScheme.error)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (deuda.nota.isNotEmpty) ...[
                          Text(deuda.nota, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                        ],
                        if (deuda.pagada && deuda.fechaPago != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.check_circle, size: 14, color: Colors.green),
                              const SizedBox(width: 6),
                              Text(
                                'Pagada el ${_formatoFecha.format(deuda.fechaPago!)}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _DatoMonto(label: 'Monto total', valor: deuda.montoTotal),
                            ),
                            Expanded(
                              child: _DatoMonto(label: 'Abonado', valor: deuda.montoAbonado),
                            ),
                            Expanded(
                              child: _DatoMonto(
                                label: 'Saldo',
                                valor: deuda.saldoPendiente,
                                destacado: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!deuda.estaSaldada || onMarcarPagado != null)
                          Row(
                            children: [
                              if (!deuda.estaSaldada)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _abrirDialogoPago(context),
                                    icon: const Icon(Icons.payments_outlined, size: 18),
                                    label: const Text('Registrar Pago'),
                                  ),
                                ),
                              if (!deuda.estaSaldada && onMarcarPagado != null)
                                const SizedBox(width: 8),
                              if (onMarcarPagado != null && !deuda.pagada)
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: onMarcarPagado,
                                    icon: const Icon(Icons.check_circle_outline, size: 18),
                                    label: const Text('Marcar Pagado'),
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Text('Historial de pagos', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        _HistorialPagos(deuda: deuda),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumeroBadge extends StatelessWidget {
  final String numero;
  const _NumeroBadge({required this.numero});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '#$numero',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _DatoMonto extends StatelessWidget {
  final String label;
  final double valor;
  final bool destacado;

  const _DatoMonto({required this.label, required this.valor, this.destacado = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          _formatoMoneda.format(valor),
          style: TextStyle(fontWeight: destacado ? FontWeight.w700 : FontWeight.w500),
        ),
      ],
    );
  }
}

/// Historial de abonos, leído desde la colección de nivel superior `pagos`
/// (filtrada por `idDeuda`). Cada abono se puede corregir o eliminar en caso
/// de error de carga.
class _HistorialPagos extends StatefulWidget {
  final DeudaModel deuda;
  const _HistorialPagos({required this.deuda});

  @override
  State<_HistorialPagos> createState() => _HistorialPagosState();
}

class _HistorialPagosState extends State<_HistorialPagos> {
  DeudaModel get deuda => widget.deuda;

  // Se incrementa cada vez que se toca "Reintentar": al cambiar, `build()`
  // vuelve a llamar a `provider.porDeuda(...)`, que crea una suscripción
  // nueva (StreamBuilder resuscribe solo apenas detecta que el Stream que
  // recibe es una instancia distinta a la anterior).
  int _intentos = 0;

  // Último snapshot de pagos recibido con éxito. Se sigue mostrando aunque
  // después llegue un evento de error puntual del stream (reconexión,
  // hiccup de red, etc.) — así un problema transitorio no reemplaza una
  // lista que ya se había cargado bien por una pantalla de error.
  List<PagoModel>? _ultimosPagos;

  // Timeout de "primera carga" únicamente: si en los primeros segundos
  // desde que nos suscribimos no llegó NINGÚN evento (ni datos ni error),
  // se muestra un error en vez de dejar el spinner girando para siempre.
  // A propósito NO es un timeout que se reinicia con cada evento del
  // stream: un listener de Firestore sano puede quedarse en silencio
  // mucho más de 15s sin que pase nada raro (simplemente no hay pagos
  // nuevos), y tratar ese silencio como un error fue justamente el bug
  // que causaba que la pantalla se rompiera sola a los pocos segundos.
  Timer? _timeoutPrimeraCarga;
  bool _huboAlgunEvento = false;
  Object? _errorPrimeraCarga;

  @override
  void initState() {
    super.initState();
    _programarTimeoutPrimeraCarga();
  }

  void _programarTimeoutPrimeraCarga() {
    _timeoutPrimeraCarga?.cancel();
    _huboAlgunEvento = false;
    _errorPrimeraCarga = null;
    _timeoutPrimeraCarga = Timer(const Duration(seconds: 15), () {
      if (!_huboAlgunEvento && mounted) {
        setState(() {
          _errorPrimeraCarga = TimeoutException(
            'La consulta a Firestore no respondió a tiempo (revisá la conexión '
            'o los permisos de la colección "pagos").',
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _timeoutPrimeraCarga?.cancel();
    super.dispose();
  }

  Future<void> _editar(
    BuildContext context,
    String pagoId,
    double montoActual,
    String notaActual,
    MedioPago medioPagoActual,
  ) async {
    final resultado = await showDialog<_PagoEditado>(
      context: context,
      builder: (context) => _EditarPagoDialog(
        deuda: deuda,
        montoActual: montoActual,
        notaActual: notaActual,
        medioPagoActual: medioPagoActual,
      ),
    );

    if (!context.mounted) return;
    if (resultado != null) {
      try {
        await context.read<DeudaProvider>().editarPago(
              deuda,
              pagoId,
              montoAnterior: montoActual,
              montoNuevo: resultado.monto,
              nota: resultado.nota,
              medioPago: resultado.medioPago.name,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pago actualizado')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al actualizar el pago: $e')),
          );
        }
      }
    }
  }

  Future<void> _eliminar(BuildContext context, String pagoId, double monto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar pago'),
        content: Text(
          '¿Eliminar el abono de ${_formatoMoneda.format(monto)}? '
          'El saldo pendiente se recalculará automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (confirmar == true) {
      try {
        await context.read<DeudaProvider>().eliminarPago(deuda, pagoId, monto);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pago eliminado')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar el pago: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PagoProvider>();

    // Ojo: esta consulta es solo `where('idDeuda', ...)`, sin `orderBy` del
    // lado de Firestore a propósito. Combinar un filtro con un orderBy en
    // otro campo requiere crear un índice compuesto en Firestore; si ese
    // índice no existe, el stream nunca emite datos y solo emite un error
    // -que antes no se mostraba en ningún lado, dejando el spinner girando
    // para siempre-. El orden (más recientes primero) se aplica acá en el
    // cliente, sobre la lista ya cargada.
    return StreamBuilder<List<PagoModel>>(
      key: ValueKey(_intentos),
      stream: provider.porDeuda(deuda.id),
      builder: (context, snapshot) {
        if (snapshot.hasData || snapshot.hasError) {
          _huboAlgunEvento = true;
        }
        if (snapshot.hasData) {
          _ultimosPagos = snapshot.data;
        }

        // Prioridad 1: si ya tenemos datos -de este evento o de uno
        // anterior-, se muestran siempre. Un error puntual después de una
        // carga exitosa (reconexión, hiccup de red) no debe reemplazar una
        // lista que ya se veía bien.
        final pagosDisponibles = _ultimosPagos;
        if (pagosDisponibles != null) {
          return _construirLista(context, pagosDisponibles);
        }

        // Prioridad 2: todavía sin datos. Si hay un error real del stream,
        // o venció el timeout de primera carga, se muestra con botón para
        // reintentar.
        final error = snapshot.hasError ? snapshot.error : _errorPrimeraCarga;
        if (error != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'No se pudo cargar el historial de pagos: $error',
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _intentos++;
                    _programarTimeoutPrimeraCarga();
                  }),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }

        // Prioridad 3: esperando el primer evento, sin timeout vencido
        // todavía.
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  /// Combina los pagos "de verdad" (documentos en la colección `pagos`,
  /// editables/eliminables) con cualquier `pagos` embebido que haya
  /// quedado en el propio documento de la deuda (por ejemplo, de una carga
  /// manual en la consola de Firebase) — así se ven en el historial sin
  /// importar dónde hayan terminado guardados.
  Widget _construirLista(BuildContext context, List<PagoModel> pagosDelStream) {
    final pagos = [...?deuda.pagos, ...pagosDelStream]
      ..sort((a, b) => b.fechaPago.compareTo(a.fechaPago));
    if (pagos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Todavía no hay pagos registrados',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return Column(
      children: pagos.map((pago) {
        final medioPago = MedioPagoExtension.fromString(pago.metodoPago);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Text(_formatoMoneda.format(pago.montoAbonado)),
              const SizedBox(width: 6),
              Tooltip(
                message: medioPago.label,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: medioPago.color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(medioPago.icon, size: 12, color: medioPago.color),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatoFecha.format(pago.fechaPago),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (pago.nota.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pago.nota,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                const Spacer(),
              // Los pagos que vinieron embebidos en el documento de la
              // deuda (id sintético "embebido-...") no tienen un
              // documento propio en la colección `pagos`: no se pueden
              // corregir ni eliminar desde acá.
              if (pago.id.startsWith('embebido-'))
                Tooltip(
                  message: 'Pago importado dentro de la deuda (no editable)',
                  child: Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade400),
                )
              else
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (accion) {
                    if (accion == 'editar') {
                      _editar(context, pago.id, pago.montoAbonado, pago.nota, medioPago);
                    }
                    if (accion == 'eliminar') _eliminar(context, pago.id, pago.montoAbonado);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'editar',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined, size: 18),
                        title: Text('Corregir'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'eliminar',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, size: 18),
                        title: Text('Eliminar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// -----------------------------------------------------------------------
/// DIÁLOGO: REGISTRAR PAGO
/// -----------------------------------------------------------------------

class _RegistrarPagoDialog extends StatefulWidget {
  final DeudaModel deuda;
  const _RegistrarPagoDialog({required this.deuda});

  @override
  State<_RegistrarPagoDialog> createState() => _RegistrarPagoDialogState();
}

class _RegistrarPagoDialogState extends State<_RegistrarPagoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  MedioPago? _medioPago;
  bool _guardando = false;
  bool _mostrarErrorMedioPago = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  String? _validarMonto(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresá un monto';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número válido';
    if (n <= 0) return 'Debe ser mayor a 0';
    if (n > widget.deuda.saldoPendiente) {
      return 'No puede superar el saldo (${_formatoMoneda.format(widget.deuda.saldoPendiente)})';
    }
    return null;
  }

  Future<void> _confirmar() async {
    final formValido = _formKey.currentState!.validate();
    final medioPago = _medioPago;
    setState(() => _mostrarErrorMedioPago = medioPago == null);
    if (!formValido || medioPago == null) return;

    setState(() => _guardando = true);
    final monto = double.parse(_montoCtrl.text.trim().replaceAll(',', '.'));

    try {
      await context.read<DeudaProvider>().registrarPago(
            widget.deuda,
            monto,
            nota: _notaCtrl.text.trim(),
            medioPago: medioPago.name,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago registrado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar el pago: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar pago'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Saldo pendiente: ${_formatoMoneda.format(widget.deuda.saldoPendiente)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montoCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto abonado', prefixText: '\$ '),
              validator: _validarMonto,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Medio de pago', style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 6),
            SegmentedButton<MedioPago>(
              emptySelectionAllowed: true,
              segments: [
                ButtonSegment(
                  value: MedioPago.transferencia,
                  label: Text(MedioPago.transferencia.label),
                  icon: Icon(MedioPago.transferencia.icon),
                ),
                ButtonSegment(
                  value: MedioPago.efectivo,
                  label: Text(MedioPago.efectivo.label),
                  icon: Icon(MedioPago.efectivo.icon),
                ),
              ],
              selected: _medioPago == null ? const {} : {_medioPago!},
              onSelectionChanged: (seleccion) => setState(() {
                _medioPago = seleccion.isEmpty ? null : seleccion.first;
                _mostrarErrorMedioPago = false;
              }),
            ),
            if (_mostrarErrorMedioPago)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Seleccioná un medio de pago',
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notaCtrl,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _confirmar,
          child: _guardando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirmar'),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// DIÁLOGO: CORREGIR PAGO
/// -----------------------------------------------------------------------

class _PagoEditado {
  final double monto;
  final String nota;
  final MedioPago medioPago;
  const _PagoEditado({required this.monto, required this.nota, required this.medioPago});
}

class _EditarPagoDialog extends StatefulWidget {
  final DeudaModel deuda;
  final double montoActual;
  final String notaActual;
  final MedioPago medioPagoActual;

  const _EditarPagoDialog({
    required this.deuda,
    required this.montoActual,
    required this.notaActual,
    required this.medioPagoActual,
  });

  @override
  State<_EditarPagoDialog> createState() => _EditarPagoDialogState();
}

class _EditarPagoDialogState extends State<_EditarPagoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _montoCtrl = TextEditingController(text: widget.montoActual.toStringAsFixed(0));
  late final _notaCtrl = TextEditingController(text: widget.notaActual);
  late MedioPago _medioPago = widget.medioPagoActual;
  bool _guardando = false;

  double get _maxPermitido => widget.deuda.saldoPendiente + widget.montoActual;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  String? _validarMonto(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresá un monto';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número válido';
    if (n <= 0) return 'Debe ser mayor a 0';
    if (n > _maxPermitido) {
      return 'No puede superar ${_formatoMoneda.format(_maxPermitido)}';
    }
    return null;
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final monto = double.parse(_montoCtrl.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop(
      _PagoEditado(monto: monto, nota: _notaCtrl.text.trim(), medioPago: _medioPago),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Corregir pago'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _montoCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
              validator: _validarMonto,
            ),
            const SizedBox(height: 12),
            SegmentedButton<MedioPago>(
              segments: [
                ButtonSegment(
                  value: MedioPago.transferencia,
                  label: Text(MedioPago.transferencia.label),
                  icon: Icon(MedioPago.transferencia.icon),
                ),
                ButtonSegment(
                  value: MedioPago.efectivo,
                  label: Text(MedioPago.efectivo.label),
                  icon: Icon(MedioPago.efectivo.icon),
                ),
              ],
              selected: {_medioPago},
              onSelectionChanged: (seleccion) => setState(() => _medioPago = seleccion.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notaCtrl,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _confirmar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// DIÁLOGO: NUEVO CLIENTE / EDITAR CLIENTE (desde el formulario de cuenta)
/// -----------------------------------------------------------------------

/// Mismo diálogo para crear un cliente nuevo y para editar uno existente
/// (por ejemplo, para completarle el teléfono si quedó sin cargar en una
/// importación — sin teléfono no aparecen los botones de Llamar/WhatsApp
/// en la tarjeta de la cuenta).
class _ClienteFormDialog extends StatefulWidget {
  final ClienteModel? cliente;
  const _ClienteFormDialog({this.cliente});

  @override
  State<_ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends State<_ClienteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombreCtrl = TextEditingController(text: widget.cliente?.nombre ?? '');
  late final _telefonoCtrl = TextEditingController(text: widget.cliente?.telefono ?? '');
  late final _notasCtrl = TextEditingController(text: widget.cliente?.notas ?? '');
  bool _guardando = false;

  bool get _esEdicion => widget.cliente != null;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final provider = context.read<ClienteProvider>();
      if (_esEdicion) {
        final actualizado = widget.cliente!.copyWith(
          nombre: _nombreCtrl.text.trim(),
          telefono: _telefonoCtrl.text.trim(),
          notas: _notasCtrl.text.trim(),
        );
        await provider.actualizar(actualizado);
        if (mounted) Navigator.of(context).pop(actualizado.id);
      } else {
        final id = await provider.agregar(
          ClienteModel(
            id: '',
            nombre: _nombreCtrl.text.trim(),
            telefono: _telefonoCtrl.text.trim(),
            notas: _notasCtrl.text.trim(),
          ),
        );
        if (mounted) Navigator.of(context).pop(id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar el cliente: $e')),
        );
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar cliente' : 'Nuevo cliente'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nombreCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'El nombre es obligatorio' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefonoCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono (opcional)',
                hintText: 'Hace falta para Llamar/WhatsApp',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notasCtrl,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _confirmar,
          child: _guardando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_esEdicion ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// FORMULARIO: NUEVA / EDITAR CUENTA (deudor o acreedor)
/// -----------------------------------------------------------------------

/// Valor centinela usado en el Dropdown de clientes para representar la
/// opción "+ Nuevo cliente" (abre [_ClienteFormDialog] en vez de
/// seleccionar un cliente existente).
const _nuevoClienteValor = '__nuevo_cliente__';

class _DeudaFormSheet extends StatefulWidget {
  final TipoDeuda tipoInicial;
  final DeudaModel? deuda;
  const _DeudaFormSheet({required this.tipoInicial, this.deuda});

  @override
  State<_DeudaFormSheet> createState() => _DeudaFormSheetState();
}

class _DeudaFormSheetState extends State<_DeudaFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _numeroDeudaCtrl = TextEditingController(text: widget.deuda?.numeroDeuda ?? '');
  late final _conceptoCtrl = TextEditingController(text: widget.deuda?.concepto ?? '');
  late final _montoTotalCtrl =
      TextEditingController(text: widget.deuda?.montoTotal.toStringAsFixed(0) ?? '');
  late final _notaCtrl = TextEditingController(text: widget.deuda?.nota ?? '');

  /// Teléfono del cliente seleccionado. Vive acá (no solo en el diálogo de
  /// "Editar cliente") para que quede visible y editable directamente en
  /// el formulario de la cuenta: es el dato que hace falta para que
  /// aparezcan los botones de Llamar/WhatsApp en la tarjeta.
  final _telefonoClienteCtrl = TextEditingController();
  bool _telefonoClienteInicializado = false;

  /// Última lista de clientes que llegó del stream, cacheada para poder
  /// buscar un cliente por id de forma sincrónica (por ejemplo, al cambiar
  /// la selección del Dropdown o al guardar).
  List<ClienteModel> _clientesCache = const [];

  late TipoDeuda _tipo;
  late DateTime _fecha;
  String? _idClienteSeleccionado;
  bool _guardando = false;
  bool _mostrarErrorCliente = false;

  bool get _esEdicion => widget.deuda != null;

  ClienteModel? _buscarClienteEnCache(String? id) {
    if (id == null) return null;
    for (final c in _clientesCache) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _tipo = widget.deuda?.tipo ?? widget.tipoInicial;
    _fecha = widget.deuda?.fechaEmision ?? DateTime.now();
    _idClienteSeleccionado = widget.deuda?.idCliente;

    if (!_esEdicion) {
      // Sugerencia autogenerada; el usuario puede sobrescribirla a mano.
      final sufijo = DateTime.now().millisecondsSinceEpoch.toString();
      _numeroDeudaCtrl.text = 'D-${sufijo.substring(sufijo.length - 6)}';
    }
  }

  @override
  void dispose() {
    _numeroDeudaCtrl.dispose();
    _conceptoCtrl.dispose();
    _montoTotalCtrl.dispose();
    _notaCtrl.dispose();
    _telefonoClienteCtrl.dispose();
    super.dispose();
  }

  String? _validarRequerido(String? value, {String campo = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) return '$campo es obligatorio';
    return null;
  }

  String? _validarMontoTotal(String? value) {
    if (value == null || value.trim().isEmpty) return 'El monto es obligatorio';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número válido';
    if (n <= 0) return 'Debe ser mayor a 0';
    final abonado = widget.deuda?.montoAbonado ?? 0;
    if (n < abonado) {
      return 'No puede ser menor a lo ya abonado (${_formatoMoneda.format(abonado)})';
    }
    return null;
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _seleccionarCliente(String? value) async {
    if (value == _nuevoClienteValor) {
      final nuevoId = await showDialog<String>(
        context: context,
        builder: (context) => const _ClienteFormDialog(),
      );
      if (nuevoId != null) {
        setState(() {
          _idClienteSeleccionado = nuevoId;
          _mostrarErrorCliente = false;
          // El teléfono ya se cargó en el diálogo de "Nuevo cliente". Lo
          // dejamos vacío hasta que el stream traiga ese cliente nuevo
          // (evita mostrar el teléfono del cliente anterior por un
          // instante) — se completa solo apenas llega, ver build().
          _telefonoClienteCtrl.clear();
          _telefonoClienteInicializado = false;
        });
      }
      return;
    }
    final cliente = _buscarClienteEnCache(value);
    setState(() {
      _idClienteSeleccionado = value;
      _mostrarErrorCliente = false;
      _telefonoClienteCtrl.text = cliente?.telefono ?? '';
      _telefonoClienteInicializado = true;
    });
  }

  /// Abre el mismo diálogo de "Nuevo cliente" pero en modo edición, para
  /// poder completarle/corregirle el teléfono a un cliente que ya existe
  /// (por ejemplo, si vino sin teléfono de una importación). Sin teléfono
  /// cargado, la tarjeta de la cuenta no muestra los botones de Llamar ni
  /// de WhatsApp.
  Future<void> _editarCliente(ClienteModel cliente) async {
    await showDialog<String>(
      context: context,
      builder: (context) => _ClienteFormDialog(cliente: cliente),
    );
    // El StreamBuilder de clientes recibe los datos actualizados solo
    // (ClienteProvider.stream escucha la colección en vivo); no hace falta
    // hacer nada más acá.
  }

  Future<void> _guardar() async {
    final formValido = _formKey.currentState!.validate();
    final idCliente = _idClienteSeleccionado;
    setState(() => _mostrarErrorCliente = idCliente == null || idCliente.isEmpty);
    if (!formValido || idCliente == null || idCliente.isEmpty) return;

    setState(() => _guardando = true);

    final base = widget.deuda;
    final montoTotal = double.parse(_montoTotalCtrl.text.trim().replaceAll(',', '.'));
    final montoAbonado = base?.montoAbonado ?? 0;
    final cuenta = DeudaModel(
      id: base?.id ?? '',
      idCliente: idCliente,
      tipo: _tipo,
      concepto: _conceptoCtrl.text.trim(),
      montoTotal: montoTotal,
      // El monto abonado se gestiona desde "Registrar Pago" / el historial,
      // no desde este formulario.
      montoAbonado: montoAbonado,
      fechaEmision: _fecha,
      estado: montoAbonado >= montoTotal ? 'pagado' : 'pendiente',
      fechaPago: base?.fechaPago,
      numeroDeuda: _numeroDeudaCtrl.text.trim(),
      nota: _notaCtrl.text.trim(),
    );

    try {
      final provider = context.read<DeudaProvider>();
      if (_esEdicion) {
        await provider.actualizar(cuenta);
      } else {
        await provider.agregar(cuenta);
      }

      // Si el teléfono del cliente cambió (lo tipeó o corrigió acá mismo),
      // lo actualizamos en su documento de `clientes` — así queda
      // disponible para Llamar/WhatsApp en todas las cuentas de esa misma
      // persona, no solo en esta. No bloquea el guardado de la cuenta si
      // falla: ya se guardó lo importante.
      final clienteActual = _buscarClienteEnCache(idCliente);
      final telefonoNuevo = _telefonoClienteCtrl.text.trim();
      if (clienteActual != null && clienteActual.telefono.trim() != telefonoNuevo) {
        try {
          await context
              .read<ClienteProvider>()
              .actualizar(clienteActual.copyWith(telefono: telefonoNuevo));
        } catch (_) {
          // Se puede corregir después desde el lápiz de "Editar cliente".
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_esEdicion ? 'Cuenta actualizada' : 'Cuenta agregada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final clienteProvider = context.watch<ClienteProvider>();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  _esEdicion ? 'Editar cuenta' : 'Nueva cuenta',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SegmentedButton<TipoDeuda>(
                  segments: const [
                    ButtonSegment(
                      value: TipoDeuda.deudor,
                      label: Text('Me deben'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                    ButtonSegment(
                      value: TipoDeuda.acreedor,
                      label: Text('Debo'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (seleccion) => setState(() => _tipo = seleccion.first),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _numeroDeudaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de cuenta',
                    hintText: 'Autogenerado, editable',
                  ),
                  validator: (v) => _validarRequerido(v, campo: 'El número de cuenta'),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<ClienteModel>>(
                  stream: clienteProvider.stream,
                  builder: (context, snapshot) {
                    final clientes = snapshot.data ?? const <ClienteModel>[];
                    _clientesCache = clientes;
                    final valorActual = clientes.any((c) => c.id == _idClienteSeleccionado)
                        ? _idClienteSeleccionado
                        : null;
                    final clienteActual = valorActual == null
                        ? null
                        : clientes.firstWhere((c) => c.id == valorActual);

                    // Primera vez que llegan los datos del cliente ya
                    // seleccionado (por ejemplo, al abrir "Editar cuenta"):
                    // precargamos su teléfono una sola vez, sin pisar lo
                    // que el usuario ya haya tipeado a mano después.
                    if (!_telefonoClienteInicializado && clienteActual != null) {
                      _telefonoClienteCtrl.text = clienteActual.telefono;
                      _telefonoClienteInicializado = true;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                // Se remonta cada vez que cambia la
                                // selección (por el usuario, tras crear un
                                // cliente nuevo, o tras editar el actual)
                                // para que `initialValue` -que solo se lee
                                // una vez, no es reactivo- siempre refleje
                                // el valor actual.
                                key: ValueKey('cliente-${valorActual ?? 'ninguno'}'),
                                initialValue: valorActual,
                                decoration: const InputDecoration(labelText: 'Cliente'),
                                isExpanded: true,
                                items: [
                                  ...clientes.map(
                                    (c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                  const DropdownMenuItem(
                                    value: _nuevoClienteValor,
                                    child: Text('+ Nuevo cliente'),
                                  ),
                                ],
                                onChanged: (value) => _seleccionarCliente(value),
                              ),
                            ),
                            if (clienteActual != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: IconButton(
                                  tooltip: clienteActual.telefono.trim().isEmpty
                                      ? 'Agregar teléfono al cliente (para Llamar/WhatsApp)'
                                      : 'Editar datos del cliente',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editarCliente(clienteActual),
                                ),
                              ),
                          ],
                        ),
                        if (_mostrarErrorCliente)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4),
                            child: Text(
                              'Seleccioná un cliente',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (valorActual != null) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _telefonoClienteCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono del cliente',
                              hintText: 'Para poder Llamar / mandar WhatsApp',
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _conceptoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    hintText: 'Ej: iPhone 13 Pro Max',
                  ),
                  validator: (v) => _validarRequerido(v, campo: 'El concepto'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _montoTotalCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Monto total', prefixText: '\$ '),
                  validator: _validarMontoTotal,
                ),
                if (_esEdicion) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ya abonado: ${_formatoMoneda.format(widget.deuda!.montoAbonado)} '
                    '(se corrige desde el historial de pagos)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                InkWell(
                  onTap: _elegirFecha,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Fecha de emisión'),
                    child: Text(_formatoFecha.format(_fecha)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notaCtrl,
                  decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_esEdicion ? 'Guardar cambios' : 'Guardar cuenta'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// DIÁLOGO: IMPORTAR DEUDAS DESDE JSON
/// -----------------------------------------------------------------------

class _ImportarJsonDialog extends StatefulWidget {
  const _ImportarJsonDialog();

  @override
  State<_ImportarJsonDialog> createState() => _ImportarJsonDialogState();
}

class _ImportarJsonDialogState extends State<_ImportarJsonDialog> {
  final _controller = TextEditingController();
  bool _importando = false;
  String? _resultadoTexto;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _importar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;

    setState(() {
      _importando = true;
      _resultadoTexto = null;
    });

    try {
      final resultado = await importarDeudasDesdeJson(texto);
      if (!mounted) return;
      final resumen =
          '${resultado.deudasCreadas} deuda(s) creada(s), ${resultado.clientesCreados} cliente(s) nuevo(s), '
          '${resultado.pagosCreados} pago(s) registrado(s).'
          '${resultado.avisos.isNotEmpty ? '\n\nAvisos:\n${resultado.avisos.join('\n')}' : ''}';
      setState(() => _resultadoTexto = resumen);
    } catch (e) {
      if (!mounted) return;
      setState(() => _resultadoTexto = 'Error al importar: $e');
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importar deudas desde JSON'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pegá un JSON con una lista de deudas (o un objeto con la clave '
              '"deudas"). Cada elemento necesita al menos "cliente" y '
              '"montoTotal"; "tipo" ("deudor"/"acreedor"), "concepto", '
              '"fechaCreacion", "estado" ("pendiente"/"pagado"), "fechaPago" '
              'y "nota" son opcionales. Si el cliente ya existe (mismo '
              'nombre), se reutiliza en vez de duplicarlo.\n\n'
              'Cada deuda puede traer además "pagos": una lista de abonos '
              '{"montoAbonado", "fechaPago", "metodoPago"}. Si la incluís, el '
              'monto abonado y el estado de la deuda se calculan solos a '
              'partir de esos pagos, y cada uno queda visible en su '
              '"Historial de pagos" al desplegar la tarjeta.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              maxLines: 10,
              minLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '[{"cliente": "Juan Pérez", "montoTotal": 150000, "tipo": "deudor"}]',
                alignLabelWithHint: true,
              ),
            ),
            if (_resultadoTexto != null) ...[
              const SizedBox(height: 10),
              Text(_resultadoTexto!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _importando ? null : _importar,
          child: _importando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Importar'),
        ),
      ],
    );
  }
}
