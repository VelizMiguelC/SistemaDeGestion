import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart'
    show
        AndroidProvider,
        AppDrawer,
        AuthProvider,
        DeudaProvider,
        GastoProvider,
        IPhoneStockProvider,
        StockEmpresaProvider;
import '../models/android_model.dart';
import '../models/deuda_model.dart';
import '../models/gasto_model.dart';
import '../models/iphone_model.dart';
import '../models/stock_empresa_model.dart';
import '../services/dolar_blue_service.dart';
import 'android_screen.dart';
import 'finanzas_screen.dart';
import 'gastos_screen.dart';
import 'ingresos_extra_screen.dart';
import 'iphones_screen.dart';

final _formatoUsd = NumberFormat.currency(locale: 'en_US', symbol: 'USD \$', decimalDigits: 0);
final _formatoArs = NumberFormat.currency(locale: 'es_AR', symbol: 'AR\$', decimalDigits: 0);

/// Cotización de referencia usada solo si todavía no llegó ninguna
/// respuesta del blue (por ejemplo, el instante en que se abre la app) o
/// si la consulta a la API falla y el usuario no la carga a mano -evita
/// que las tarjetas del dashboard queden en blanco mientras se resuelve-.
const double _tasaCambioPorDefecto = 1000;

/// Paleta de acento por categoría de negocio, reutilizada en toda la
/// pantalla (acciones rápidas, tarjetas de métricas y gráfico de stock).
const Color _colorIphone = Color(0xFF0A84FF); // Azul iOS
const Color _colorAndroid = Color(0xFF12B886); // Verde menta / esmeralda
const Color _colorGastos = Color(0xFFD2691E); // Naranja terracota
const Color _colorFinanzas = Color(0xFF2F5AA8); // Violeta / azul de banco
const Color _colorAccesorios = Color(0xFFFF9F0A); // Naranja cálido (accesorios)
const Color _colorIngresoExtra = Color(0xFF34C759); // Verde (reparaciones/otros ingresos)
const Color _colorUnidades = Color(0xFF00C7BE); // Teal

/// Sombra suave y consistente para las tarjetas del dashboard.
List<BoxShadow> _sombraTarjeta(Color color) => [
      BoxShadow(
        color: color.withValues(alpha: 0.14),
        blurRadius: 14,
        offset: const Offset(0, 6),
      ),
    ];

/// -----------------------------------------------------------------------
/// PANTALLA: DASHBOARD
/// -----------------------------------------------------------------------

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Cotización del dólar blue, única fuente para todo lo que muestra el
  /// Dashboard (el chip de la AppBar y las equivalencias "≈ AR$..." de las
  /// tarjetas) -reemplaza al tipo de cambio manual que antes se guardaba en
  /// Firestore-. Se busca sola al entrar; mientras no resuelva, o si la
  /// consulta falla, se usa [_tasaCambioPorDefecto] para no dejar las
  /// tarjetas en blanco.
  bool _buscandoBlue = true;
  double? _tasaBlue;
  bool _blueFallo = false;

  @override
  void initState() {
    super.initState();
    _buscarBlue();
  }

  Future<void> _buscarBlue() async {
    setState(() {
      _buscandoBlue = true;
      _blueFallo = false;
    });
    // Límite duro además del timeout propio del servicio, para que el chip
    // nunca quede pegado buscando pase lo que pase con la conexión.
    final cotizacion = await Future.any([
      DolarBlueService().obtenerCotizacion(),
      Future.delayed(const Duration(seconds: 10), () => null),
    ]);
    if (!mounted) return;
    setState(() {
      _buscandoBlue = false;
      _tasaBlue = cotizacion?.venta;
      _blueFallo = cotizacion == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final iphoneProvider = context.watch<IPhoneStockProvider>();
    final androidProvider = context.watch<AndroidProvider>();
    final stockEmpresaProvider = context.watch<StockEmpresaProvider>();
    final deudaProvider = context.watch<DeudaProvider>();
    final gastoProvider = context.watch<GastoProvider>();
    final tasaCambio = _tasaBlue ?? _tasaCambioPorDefecto;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _DolarBlueChip(
                buscando: _buscandoBlue,
                venta: _tasaBlue,
                fallo: _blueFallo,
                onTap: _buscandoBlue ? null : _buscarBlue,
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<IPhoneModel>>(
        stream: iphoneProvider.stream,
        builder: (context, snapIphones) {
          return StreamBuilder<List<AndroidModel>>(
            stream: androidProvider.stream,
            builder: (context, snapAndroids) {
              return StreamBuilder<List<StockEmpresaModel>>(
                stream: stockEmpresaProvider.stream,
                builder: (context, snapAccesorios) {
                  return StreamBuilder<List<DeudaModel>>(
                    stream: deudaProvider.stream,
                    builder: (context, snapDeudas) {
                      return StreamBuilder<List<GastoModel>>(
                        stream: gastoProvider.stream,
                        builder: (context, snapGastos) {
                          // El error se revisa ANTES que "está cargando": un stream
                          // que falla nunca llega a tener datos (hasData queda en
                          // false para siempre), así que si el orden fuera al revés
                          // esta pantalla se quedaría en el spinner de carga sin fin
                          // y el mensaje de error de abajo jamás se mostraría.
                          final error = snapIphones.error ??
                              snapAndroids.error ??
                              snapAccesorios.error ??
                              snapDeudas.error ??
                              snapGastos.error;
                          if (error != null) {
                            return Center(child: Text('Error al cargar el dashboard: $error'));
                          }

                          final cargando = !snapIphones.hasData ||
                              !snapAndroids.hasData ||
                              !snapAccesorios.hasData ||
                              !snapDeudas.hasData ||
                              !snapGastos.hasData;
                          if (cargando) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          return _DashboardBody(
                            iphones: snapIphones.data!,
                            androids: snapAndroids.data!,
                            accesorios: snapAccesorios.data!,
                            deudas: snapDeudas.data!,
                            gastos: snapGastos.data!,
                            tasaCambio: tasaCambio,
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// CHIP: COTIZACIÓN DEL DÓLAR BLUE
/// -----------------------------------------------------------------------

/// Chip chico y siempre visible (va en la AppBar del Dashboard) con la
/// cotización de venta del dólar blue del momento, consultada a
/// dolarapi.com. Muestra el estado que le pasa [_DashboardScreenState] (es
/// la misma cotización que usan las tarjetas de abajo para las
/// equivalencias en pesos) y se puede tocar para refrescar.
class _DolarBlueChip extends StatelessWidget {
  final bool buscando;
  final double? venta;
  final bool fallo;
  final VoidCallback? onTap;

  const _DolarBlueChip({
    required this.buscando,
    required this.venta,
    required this.fallo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Verde, el mismo acento que usan "Ingresos"/"Otros ingresos" en el
    // resto de la app -con fondo suave, para que se lea bien tanto en el
    // AppBar claro de esta app como en modo oscuro del sistema-.
    const color = _colorIngresoExtra;

    String texto;
    IconData icono;
    if (buscando) {
      texto = 'Blue...';
      icono = Icons.hourglass_top_rounded;
    } else if (fallo || venta == null) {
      texto = 'Blue: --';
      icono = Icons.error_outline_rounded;
    } else {
      texto = 'Blue \$${venta!.toStringAsFixed(0)}';
      icono = Icons.attach_money_rounded;
    }

    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (buscando)
                const SizedBox(
                  height: 12,
                  width: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(icono, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                texto,
                style: const TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// CUERPO DEL DASHBOARD (ya con todos los datos cargados)
/// -----------------------------------------------------------------------

class _DashboardBody extends StatelessWidget {
  final List<IPhoneModel> iphones;
  final List<AndroidModel> androids;
  final List<StockEmpresaModel> accesorios;
  final List<DeudaModel> deudas;
  final List<GastoModel> gastos;
  final double tasaCambio;

  const _DashboardBody({
    required this.iphones,
    required this.androids,
    required this.accesorios,
    required this.deudas,
    required this.gastos,
    required this.tasaCambio,
  });

  @override
  Widget build(BuildContext context) {
    final iphonesDisponibles = iphones.where((e) => !e.vendido).toList();
    final androidsDisponibles = androids.where((e) => !e.vendido).toList();

    final inversionTotalUsd = iphonesDisponibles.fold<double>(0, (s, e) => s + e.costo) +
        androidsDisponibles.fold<double>(0, (s, e) => s + e.costo);

    final unidadesDisponibles = iphonesDisponibles.length + androidsDisponibles.length;

    final totalPorCobrarArs = deudas
        .where((d) => d.tipo == TipoDeuda.deudor)
        .fold<double>(0, (s, d) => s + d.saldoPendiente);

    final ahora = DateTime.now();
    bool vendidoEsteMes(bool vendido, DateTime? fecha) =>
        vendido && fecha != null && fecha.year == ahora.year && fecha.month == ahora.month;

    final ventasDelMes = iphones.where((e) => vendidoEsteMes(e.vendido, e.fechaVenta)).length +
        androids.where((e) => vendidoEsteMes(e.vendido, e.fechaVenta)).length;

    bool enGarantiaActiva(bool vendido, TiempoGarantiaRestante? g) =>
        vendido && g != null && !g.vencida;
    bool enGarantiaActivaAndroid(bool vendido, TiempoGarantiaRestanteAndroid? g) =>
        vendido && g != null && !g.vencida;

    final enGarantia = iphones.where((e) => enGarantiaActiva(e.vendido, e.tiempoGarantiaRestante)).length +
        androids
            .where((e) => enGarantiaActivaAndroid(e.vendido, e.tiempoGarantiaRestante))
            .length;

    final gastosEsteMes =
        gastos.where((g) => g.fecha.year == ahora.year && g.fecha.month == ahora.month).toList();
    final gastosMesArs = gastosEsteMes
        .where((g) => g.moneda == MonedaGasto.ars)
        .fold<double>(0, (s, g) => s + g.monto);
    final gastosMesUsd = gastosEsteMes
        .where((g) => g.moneda == MonedaGasto.usd)
        .fold<double>(0, (s, g) => s + g.monto);

    final accesoriosUnidades = accesorios.fold<int>(0, (s, item) => s + item.cantidad);

    return RefreshIndicator(
      onRefresh: () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Saludo(),
            const SizedBox(height: 20),
            _SeccionTitulo('Acciones rápidas'),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.5,
              children: [
                _AccionRapidaCard(
                  icon: Icons.phone_iphone_rounded,
                  color: _colorIphone,
                  label: 'Nuevo iPhone',
                  // Abre el formulario directo como modal (sin navegar antes
                  // a la pantalla completa de stock) para que "Cancelar" o
                  // "Guardar" vuelvan limpiamente al Dashboard.
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const IPhoneFormSheet(),
                  ),
                ),
                _AccionRapidaCard(
                  icon: Icons.android_rounded,
                  color: _colorAndroid,
                  label: 'Nuevo Android',
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const AndroidFormSheet(),
                  ),
                ),
                _AccionRapidaCard(
                  icon: Icons.payments_outlined,
                  color: _colorFinanzas,
                  label: 'Registrar Pago',
                  // Se muestra como modal (hoja completa) en vez de un push
                  // tradicional; conserva su propia AppBar/Drawer y se puede
                  // cerrar con el botón de volver o deslizando hacia abajo.
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const FinanzasScreen(),
                  ),
                ),
                _AccionRapidaCard(
                  icon: Icons.receipt_long_rounded,
                  color: _colorGastos,
                  label: 'Agregar Gasto',
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const GastoFormSheet(),
                  ),
                ),
                _AccionRapidaCard(
                  icon: Icons.handyman_rounded,
                  color: _colorIngresoExtra,
                  label: 'Agregar Ingreso',
                  // Reparaciones, arreglos u otros ingresos que no vienen de
                  // la venta de un equipo (ver ingresos_extra_screen.dart).
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const IngresoExtraFormSheet(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _TasaCambioInfo(tasaCambio: tasaCambio),
            const SizedBox(height: 24),
            _SeccionTitulo('Resumen financiero'),
            const SizedBox(height: 4),
            Text(
              'iPhones + Android combinados',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.15,
              children: [
                _MetricCard(
                  icon: Icons.inventory_2_outlined,
                  color: _colorIphone,
                  titulo: 'Inversión en stock',
                  valorPrincipal: _formatoUsd.format(inversionTotalUsd),
                  valorSecundario: '≈ ${_formatoArs.format(inversionTotalUsd * tasaCambio)}',
                ),
                _MetricCard(
                  icon: Icons.widgets_outlined,
                  color: _colorUnidades,
                  titulo: 'Unidades disponibles',
                  valorPrincipal: '$unidadesDisponibles',
                  valorSecundario: 'iPhones + Android',
                ),
                _MetricCard(
                  icon: Icons.sell_outlined,
                  color: _colorAndroid,
                  titulo: 'Ventas de este mes',
                  valorPrincipal: '$ventasDelMes',
                  valorSecundario: 'iPhones + Android',
                ),
                _MetricCard(
                  icon: Icons.request_quote_outlined,
                  color: _colorFinanzas,
                  titulo: 'Por cobrar (deudores)',
                  valorPrincipal: _formatoArs.format(totalPorCobrarArs),
                  valorSecundario: '≈ '
                      '${_formatoUsd.format(tasaCambio == 0 ? 0 : totalPorCobrarArs / tasaCambio)}',
                ),
                _MetricCard(
                  icon: Icons.trending_down,
                  color: _colorGastos,
                  titulo: 'Gastos de este mes',
                  valorPrincipal: _formatoArs.format(gastosMesArs),
                  valorSecundario:
                      gastosMesUsd > 0 ? '+ ${_formatoUsd.format(gastosMesUsd)}' : 'Sin gastos en USD',
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SeccionTitulo('Distribución de stock disponible'),
            const SizedBox(height: 10),
            _DistribucionStockCard(
              iphones: iphonesDisponibles.length,
              androids: androidsDisponibles.length,
              accesorios: accesoriosUnidades,
            ),
            const SizedBox(height: 24),
            _SeccionTitulo('Resumen de inventario'),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.8,
              children: [
                _StatTile(
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  valor: '$unidadesDisponibles',
                  label: 'Disponibles',
                ),
                _StatTile(
                  icon: Icons.sell_outlined,
                  color: Colors.blueGrey,
                  valor: '$ventasDelMes',
                  label: 'Vendidos\neste mes',
                ),
                _StatTile(
                  icon: Icons.shield_outlined,
                  color: Colors.blue,
                  valor: '$enGarantia',
                  label: 'En garantía\nactiva',
                ),
                _StatTile(
                  icon: Icons.inventory_2_outlined,
                  color: _colorAccesorios,
                  valor: '$accesoriosUnidades',
                  label: 'Accesorios\nen stock',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// SALUDO
/// -----------------------------------------------------------------------

class _Saludo extends StatelessWidget {
  const _Saludo();

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final email = authProvider.usuarioActual?.email ?? '';
    final nombre = email.contains('@') ? email.split('@').first : 'de nuevo';
    final fechaHoy = DateFormat('dd/MM/yyyy').format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hola, $nombre',
          style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          'Resumen del $fechaHoy',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// BARRA DE TIPO DE CAMBIO (informativa: dólar blue en vivo)
/// -----------------------------------------------------------------------

/// Solo informativa -no editable-: el tipo de cambio usado para las
/// equivalencias en pesos de este Dashboard es siempre el dólar blue en
/// vivo (chip de la AppBar), no un valor cargado a mano.
class _TasaCambioInfo extends StatelessWidget {
  final double tasaCambio;
  const _TasaCambioInfo({required this.tasaCambio});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.currency_exchange, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tipo de cambio (dólar blue): USD 1 = ${_formatoArs.format(tasaCambio)}',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// GRÁFICO: DISTRIBUCIÓN DE STOCK (fl_chart, dona)
/// -----------------------------------------------------------------------

class _DistribucionStockCard extends StatelessWidget {
  final int iphones;
  final int androids;
  final int accesorios;

  const _DistribucionStockCard({
    required this.iphones,
    required this.androids,
    required this.accesorios,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = iphones + androids + accesorios;

    final secciones = <PieChartSectionData>[
      if (iphones > 0)
        PieChartSectionData(
          value: iphones.toDouble(),
          color: _colorIphone,
          radius: 26,
          showTitle: false,
        ),
      if (androids > 0)
        PieChartSectionData(
          value: androids.toDouble(),
          color: _colorAndroid,
          radius: 26,
          showTitle: false,
        ),
      if (accesorios > 0)
        PieChartSectionData(
          value: accesorios.toDouble(),
          color: _colorAccesorios,
          radius: 26,
          showTitle: false,
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: total == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Todavía no hay stock cargado',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: secciones,
                          sectionsSpace: 3,
                          centerSpaceRadius: 38,
                          startDegreeOffset: -90,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'unidades',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LeyendaStock(
                        color: _colorIphone,
                        label: 'iPhones',
                        valor: iphones,
                        total: total,
                      ),
                      const SizedBox(height: 10),
                      _LeyendaStock(
                        color: _colorAndroid,
                        label: 'Androids',
                        valor: androids,
                        total: total,
                      ),
                      const SizedBox(height: 10),
                      _LeyendaStock(
                        color: _colorAccesorios,
                        label: 'Accesorios',
                        valor: accesorios,
                        total: total,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _LeyendaStock extends StatelessWidget {
  final Color color;
  final String label;
  final int valor;
  final int total;

  const _LeyendaStock({
    required this.color,
    required this.label,
    required this.valor,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final porcentaje = total == 0 ? 0 : (valor / total * 100).round();
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          '$valor · $porcentaje%',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// COMPONENTES DE UI
/// -----------------------------------------------------------------------

class _SeccionTitulo extends StatelessWidget {
  final String texto;
  const _SeccionTitulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titulo;
  final String valorPrincipal;
  final String valorSecundario;

  const _MetricCard({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.valorPrincipal,
    required this.valorSecundario,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.04)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: _sombraTarjeta(color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: color),
              ),
            ],
          ),
          const Spacer(),
          Text(
            titulo,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valorPrincipal,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          Text(
            valorSecundario,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String valor;
  final String label;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.valor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: _sombraTarjeta(color),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            valor,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Botón de acción rápida estilo tarjeta horizontal (ícono + etiqueta),
/// pensado para una cuadrícula de 2 columnas en la parte superior del
/// dashboard.
class _AccionRapidaCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _AccionRapidaCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.05)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            boxShadow: _sombraTarjeta(color),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
