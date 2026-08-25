import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart' show AndroidProvider, AppDrawer, GastoProvider, IPhoneStockProvider;
import '../models/android_model.dart';
import '../models/gasto_model.dart';
import '../models/iphone_model.dart';

final _formatoUsd = NumberFormat.currency(locale: 'en_US', symbol: 'USD \$', decimalDigits: 0);

/// Documento con el tipo de cambio manual USD → ARS (el mismo que usa el
/// Dashboard), necesario para poder sumar los gastos operativos -que pueden
/// cargarse en ARS o en USD- en una sola métrica en dólares.
final _tasaCambioRef = FirebaseFirestore.instance.collection('configuracion').doc('tasaCambio');
const double _tasaCambioPorDefecto = 1000;

const List<String> _nombresMeses = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

const List<String> _nombresMesesAbrev = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
];

/// Paleta de acento de esta pantalla (coherente con la del Dashboard).
const Color _colorIngresos = Color(0xFF34C759); // Verde
const Color _colorCosto = Color(0xFF5856D6); // Violeta
const Color _colorGananciaBruta = Color(0xFF0A84FF); // Azul
const Color _colorGastosOperativos = Color(0xFFFF9500); // Naranja

/// Color por categoría, solo para uso visual de esta pantalla (independiente
/// del que ya existe en `gastos_screen.dart`, que es privado a ese archivo).
extension _CategoriaGastoUi on CategoriaGasto {
  Color get color {
    switch (this) {
      case CategoriaGasto.alquiler:
        return Colors.purple;
      case CategoriaGasto.insumos:
        return Colors.orange;
      case CategoriaGasto.servicios:
        return Colors.blue;
      case CategoriaGasto.importacion:
        return Colors.teal;
      case CategoriaGasto.personal:
        return Colors.pink;
      case CategoriaGasto.varios:
        return Colors.blueGrey;
    }
  }
}

/// Vista de agrupación del reporte.
enum VistaReporte { mensual, anual }

/// -----------------------------------------------------------------------
/// PANTALLA: BALANCE & REPORTES
/// -----------------------------------------------------------------------

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  VistaReporte _vista = VistaReporte.mensual;
  int _mes = DateTime.now().month;
  int _anio = DateTime.now().year;

  /// Convierte un gasto a su equivalente en USD usando la tasa de cambio.
  double _gastoEnUsd(GastoModel gasto, double tasaCambio) {
    if (gasto.moneda == MonedaGasto.usd) return gasto.monto;
    if (tasaCambio == 0) return 0;
    return gasto.monto / tasaCambio;
  }

  bool _fechaEnPeriodo(DateTime fecha, {int? mes}) {
    if (fecha.year != _anio) return false;
    if (mes != null && fecha.month != mes) return false;
    return true;
  }

  bool _vendidoEnPeriodo(bool vendido, DateTime? fecha, {int? mes}) {
    return vendido && fecha != null && _fechaEnPeriodo(fecha, mes: mes);
  }

  @override
  Widget build(BuildContext context) {
    final iphoneProvider = context.watch<IPhoneStockProvider>();
    final androidProvider = context.watch<AndroidProvider>();
    final gastoProvider = context.watch<GastoProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      // Fondo suave (no blanco plano), consistente con el resto de la app.
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      drawer: const AppDrawer(),
      appBar: AppBar(title: const Text('Balance & Reportes')),
      body: StreamBuilder<List<IPhoneModel>>(
        stream: iphoneProvider.stream,
        builder: (context, snapshotIphones) {
          return StreamBuilder<List<AndroidModel>>(
            stream: androidProvider.stream,
            builder: (context, snapshotAndroids) {
              return StreamBuilder<List<GastoModel>>(
                stream: gastoProvider.stream,
                builder: (context, snapshotGastos) {
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _tasaCambioRef.snapshots(),
                    builder: (context, snapshotTasa) {
                      final cargando = !snapshotIphones.hasData ||
                          !snapshotAndroids.hasData ||
                          !snapshotGastos.hasData;
                      if (cargando) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final error =
                          snapshotIphones.error ?? snapshotAndroids.error ?? snapshotGastos.error;
                      if (error != null) {
                        return Center(child: Text('Error al cargar el reporte: $error'));
                      }

                      final todosIphones = snapshotIphones.data!;
                      final todosAndroids = snapshotAndroids.data!;
                      final todosGastos = snapshotGastos.data!;
                      final tasaCambio =
                          (snapshotTasa.data?.data()?['valor'] as num?)?.toDouble() ??
                              _tasaCambioPorDefecto;

                      final mesFiltro = _vista == VistaReporte.mensual ? _mes : null;

                      final iphonesVendidosPeriodo = todosIphones
                          .where((e) => _vendidoEnPeriodo(e.vendido, e.fechaVenta, mes: mesFiltro))
                          .toList();
                      final androidsVendidosPeriodo = todosAndroids
                          .where((e) => _vendidoEnPeriodo(e.vendido, e.fechaVenta, mes: mesFiltro))
                          .toList();

                      final gastosPeriodo = todosGastos
                          .where((g) => _fechaEnPeriodo(g.fecha, mes: mesFiltro))
                          .toList();

                      // Ingresos, costo y ganancia bruta ahora combinan las
                      // ventas de iPhones y de equipos Android.
                      final ingresosUsd = iphonesVendidosPeriodo
                              .fold<double>(0, (s, e) => s + (e.precioVenta ?? 0)) +
                          androidsVendidosPeriodo.fold<double>(0, (s, e) => s + (e.precioVenta ?? 0));
                      final costoUsd =
                          iphonesVendidosPeriodo.fold<double>(0, (s, e) => s + e.costo) +
                              androidsVendidosPeriodo.fold<double>(0, (s, e) => s + e.costo);
                      final gananciaBrutaUsd = ingresosUsd - costoUsd;
                      final gastosOperativosUsd = gastosPeriodo.fold<double>(
                        0,
                        (s, g) => s + _gastoEnUsd(g, tasaCambio),
                      );
                      final gananciaNetaUsd = gananciaBrutaUsd - gastosOperativosUsd;
                      final equiposVendidosPeriodo =
                          iphonesVendidosPeriodo.length + androidsVendidosPeriodo.length;

                      // Desglose de gastos por categoría (en USD equivalente).
                      final Map<CategoriaGasto, double> porCategoria = {};
                      for (final g in gastosPeriodo) {
                        porCategoria.update(
                          g.categoria,
                          (valor) => valor + _gastoEnUsd(g, tasaCambio),
                          ifAbsent: () => _gastoEnUsd(g, tasaCambio),
                        );
                      }
                      final categoriasOrdenadas = porCategoria.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value));

                      // Años disponibles según los datos + el año actual.
                      final anios = <int>{
                        DateTime.now().year,
                        _anio,
                        ...todosIphones
                            .where((e) => e.fechaVenta != null)
                            .map((e) => e.fechaVenta!.year),
                        ...todosAndroids
                            .where((e) => e.fechaVenta != null)
                            .map((e) => e.fechaVenta!.year),
                        ...todosGastos.map((g) => g.fecha.year),
                      }.toList()
                        ..sort((a, b) => b.compareTo(a));

                      // Desglose mensual acumulado (solo en vista anual),
                      // combinando también las ventas de Android.
                      List<_ResumenMes>? resumenMensual;
                      if (_vista == VistaReporte.anual) {
                        resumenMensual = List.generate(12, (i) {
                          final mes = i + 1;
                          final iphonesMes = todosIphones.where(
                            (e) => _vendidoEnPeriodo(e.vendido, e.fechaVenta, mes: mes),
                          );
                          final androidsMes = todosAndroids.where(
                            (e) => _vendidoEnPeriodo(e.vendido, e.fechaVenta, mes: mes),
                          );
                          final gastosMes =
                              todosGastos.where((g) => _fechaEnPeriodo(g.fecha, mes: mes));

                          final ingresosMes =
                              iphonesMes.fold<double>(0, (s, e) => s + (e.precioVenta ?? 0)) +
                                  androidsMes.fold<double>(0, (s, e) => s + (e.precioVenta ?? 0));
                          final costoMes = iphonesMes.fold<double>(0, (s, e) => s + e.costo) +
                              androidsMes.fold<double>(0, (s, e) => s + e.costo);
                          final gastosMesUsd = gastosMes.fold<double>(
                            0,
                            (s, g) => s + _gastoEnUsd(g, tasaCambio),
                          );

                          return _ResumenMes(
                            mes: mes,
                            ingresos: ingresosMes,
                            costo: costoMes,
                            gastosUsd: gastosMesUsd,
                            equiposVendidos: iphonesMes.length + androidsMes.length,
                          );
                        });
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SelectorPeriodo(
                              vista: _vista,
                              mes: _mes,
                              anio: _anio,
                              aniosDisponibles: anios,
                              onVistaChanged: (v) => setState(() => _vista = v),
                              onMesChanged: (m) => setState(() => _mes = m),
                              onAnioChanged: (a) => setState(() => _anio = a),
                            ),
                            const SizedBox(height: 20),
                            _GananciaNetaBanner(monto: gananciaNetaUsd),
                            const SizedBox(height: 16),
                            Text(
                              '$equiposVendidosPeriodo equipos vendidos (iPhones + Android)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.3,
                              children: [
                                _KpiCard(
                                  icon: Icons.arrow_downward,
                                  color: _colorIngresos,
                                  titulo: 'Ingresos totales',
                                  valor: _formatoUsd.format(ingresosUsd),
                                ),
                                _KpiCard(
                                  icon: Icons.attach_money,
                                  color: _colorCosto,
                                  titulo: 'Costo de equipos',
                                  valor: _formatoUsd.format(costoUsd),
                                ),
                                _KpiCard(
                                  icon: Icons.trending_up,
                                  color: _colorGananciaBruta,
                                  titulo: 'Ganancia bruta',
                                  subtitulo: 'iPhones + Android',
                                  valor: _formatoUsd.format(gananciaBrutaUsd),
                                ),
                                _KpiCard(
                                  icon: Icons.trending_down,
                                  color: _colorGastosOperativos,
                                  titulo: 'Gastos operativos',
                                  valor: _formatoUsd.format(gastosOperativosUsd),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Gastos por categoría',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (categoriasOrdenadas.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'No hay gastos registrados en este período',
                                  style: theme.textTheme.bodySmall,
                                ),
                              )
                            else
                              _GastosCategoriaCard(
                                filas: categoriasOrdenadas,
                                total: gastosOperativosUsd,
                              ),
                            if (resumenMensual != null) ...[
                              const SizedBox(height: 24),
                              Text(
                                'Ganancias vs. Gastos · $_anio',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _GananciasVsGastosChart(filas: resumenMensual),
                              const SizedBox(height: 24),
                              Text(
                                'Desglose mensual $_anio',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _TablaMensual(filas: resumenMensual),
                            ],
                          ],
                        ),
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

class _ResumenMes {
  final int mes;
  final double ingresos;
  final double costo;
  final double gastosUsd;
  final int equiposVendidos;

  const _ResumenMes({
    required this.mes,
    required this.ingresos,
    required this.costo,
    required this.gastosUsd,
    required this.equiposVendidos,
  });

  double get gananciaBruta => ingresos - costo;
  double get gananciaNeta => gananciaBruta - gastosUsd;
}

/// -----------------------------------------------------------------------
/// SELECTOR DE PERÍODO
/// -----------------------------------------------------------------------

class _SelectorPeriodo extends StatelessWidget {
  final VistaReporte vista;
  final int mes;
  final int anio;
  final List<int> aniosDisponibles;
  final ValueChanged<VistaReporte> onVistaChanged;
  final ValueChanged<int> onMesChanged;
  final ValueChanged<int> onAnioChanged;

  const _SelectorPeriodo({
    required this.vista,
    required this.mes,
    required this.anio,
    required this.aniosDisponibles,
    required this.onVistaChanged,
    required this.onMesChanged,
    required this.onAnioChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<VistaReporte>(
              segments: const [
                ButtonSegment(
                  value: VistaReporte.mensual,
                  label: Text('Vista mensual'),
                  icon: Icon(Icons.calendar_view_month),
                ),
                ButtonSegment(
                  value: VistaReporte.anual,
                  label: Text('Vista anual'),
                  icon: Icon(Icons.calendar_today),
                ),
              ],
              selected: {vista},
              onSelectionChanged: (seleccion) => onVistaChanged(seleccion.first),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (vista == VistaReporte.mensual) ...[
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: mes,
                    decoration: const InputDecoration(labelText: 'Mes', isDense: true),
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(value: m, child: Text(_nombresMeses[m - 1])))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onMesChanged(value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: anio,
                  decoration: const InputDecoration(labelText: 'Año', isDense: true),
                  items: aniosDisponibles
                      .map((a) => DropdownMenuItem(value: a, child: Text('$a')))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onAnioChanged(value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// BANNER: GANANCIA NETA REAL
/// -----------------------------------------------------------------------

class _GananciaNetaBanner extends StatelessWidget {
  final double monto;
  const _GananciaNetaBanner({required this.monto});

  @override
  Widget build(BuildContext context) {
    final color = monto >= 0 ? Colors.green : Colors.red;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                'Ganancia neta real',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatoUsd.format(monto),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Ganancia bruta (iPhones + Android) − Gastos operativos',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// TARJETA KPI
/// -----------------------------------------------------------------------

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titulo;
  final String? subtitulo;
  final String valor;

  const _KpiCard({
    required this.icon,
    required this.color,
    required this.titulo,
    this.subtitulo,
    required this.valor,
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
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const Spacer(),
          Text(titulo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          if (subtitulo != null)
            Text(
              subtitulo!,
              style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// GRÁFICO: GASTOS POR CATEGORÍA (dona + leyenda)
/// -----------------------------------------------------------------------

class _GastosCategoriaCard extends StatelessWidget {
  final List<MapEntry<CategoriaGasto, double>> filas;
  final double total;

  const _GastosCategoriaCard({required this.filas, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final secciones = filas
        .map(
          (entry) => PieChartSectionData(
            value: entry.value <= 0 ? 0.01 : entry.value,
            color: entry.key.color,
            radius: 26,
            showTitle: false,
          ),
        )
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: PieChart(
              PieChartData(
                sections: secciones,
                sectionsSpace: 3,
                centerSpaceRadius: 30,
                startDegreeOffset: -90,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: filas.map((entry) {
                final categoria = entry.key;
                final monto = entry.value;
                final porcentaje = total == 0 ? 0 : (monto / total * 100).round();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: categoria.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          categoria.label,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '$porcentaje%',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatoUsd.format(monto),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// GRÁFICO: GANANCIAS VS GASTOS MES A MES (barras, vista anual)
/// -----------------------------------------------------------------------

class _GananciasVsGastosChart extends StatelessWidget {
  final List<_ResumenMes> filas;
  const _GananciasVsGastosChart({required this.filas});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final valoresGanancia = filas.map((r) => r.gananciaBruta).toList();
    final valoresGastos = filas.map((r) => r.gastosUsd).toList();
    final maxValor = [...valoresGanancia, ...valoresGastos]
        .fold<double>(0, (m, v) => v > m ? v : m);
    final minValor = valoresGanancia.fold<double>(0, (m, v) => v < m ? v : m);
    final maxY = maxValor <= 0 ? 100.0 : maxValor * 1.25;
    final minY = minValor >= 0 ? 0.0 : minValor * 1.25;

    final barGroups = filas.asMap().entries.map((entry) {
      final i = entry.key;
      final r = entry.value;
      return BarChartGroupData(
        x: i,
        barsSpace: 4,
        barRods: [
          BarChartRodData(
            toY: r.gananciaBruta,
            color: _colorGananciaBruta,
            width: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          BarChartRodData(
            toY: r.gastosUsd,
            color: _colorGastosOperativos,
            width: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      );
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LeyendaChip(color: _colorGananciaBruta, label: 'Ganancia bruta'),
              const SizedBox(width: 16),
              _LeyendaChip(color: _colorGastosOperativos, label: 'Gastos'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                barGroups: barGroups,
                maxY: maxY,
                minY: minY,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= _nombresMesesAbrev.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _nombresMesesAbrev[i],
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeyendaChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LeyendaChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// TABLA: DESGLOSE MENSUAL (vista anual)
/// -----------------------------------------------------------------------

class _TablaMensual extends StatelessWidget {
  final List<_ResumenMes> filas;
  const _TablaMensual({required this.filas});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: filas.map((r) {
          final color = r.gananciaNeta >= 0 ? Colors.green : Colors.red;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(_nombresMeses[r.mes - 1], style: theme.textTheme.bodyMedium),
                ),
                Expanded(
                  child: Text(
                    '${r.equiposVendidos} ${r.equiposVendidos == 1 ? "equipo" : "equipos"}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  _formatoUsd.format(r.gananciaNeta),
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
