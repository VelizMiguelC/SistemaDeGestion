import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart' show AppDrawer, IngresoExtraProvider;
import '../models/gasto_model.dart' show MedioPago, MedioPagoExtension, MonedaGasto, MonedaGastoExtension;
import '../models/ingreso_extra_model.dart';

final _formatoArs = NumberFormat.currency(locale: 'es_AR', symbol: 'AR\$', decimalDigits: 0);
final _formatoUsd = NumberFormat.currency(locale: 'en_US', symbol: 'USD \$', decimalDigits: 0);
final _formatoFecha = DateFormat('dd/MM/yyyy');

const Color _colorIngresoExtra = Color(0xFF34C759); // Verde, igual que "Ingresos" en Reportes

String _formatoMonto(double monto, MonedaGasto moneda) {
  return moneda == MonedaGasto.usd ? _formatoUsd.format(monto) : _formatoArs.format(monto);
}

/// Período rápido para filtrar la lista, igual que en Gastos.
enum PeriodoIngresoExtra { esteMes, mesAnterior, todos }

extension _PeriodoIngresoExtraExtension on PeriodoIngresoExtra {
  String get label {
    switch (this) {
      case PeriodoIngresoExtra.esteMes:
        return 'Este mes';
      case PeriodoIngresoExtra.mesAnterior:
        return 'Mes anterior';
      case PeriodoIngresoExtra.todos:
        return 'Todos';
    }
  }
}

/// Color e ícono según el medio de pago, solo para uso visual (igual que en
/// gastos_screen.dart, pero privado a este archivo).
extension _MedioPagoUi on MedioPago {
  Color get color => this == MedioPago.transferencia ? Colors.blue : Colors.green;

  IconData get icon =>
      this == MedioPago.transferencia ? Icons.account_balance : Icons.payments;
}

/// -----------------------------------------------------------------------
/// PANTALLA: OTROS INGRESOS (reparaciones, arreglos, servicios varios)
/// -----------------------------------------------------------------------

class IngresosExtraScreen extends StatefulWidget {
  const IngresosExtraScreen({super.key});

  @override
  State<IngresosExtraScreen> createState() => _IngresosExtraScreenState();
}

class _IngresosExtraScreenState extends State<IngresosExtraScreen> {
  PeriodoIngresoExtra _periodo = PeriodoIngresoExtra.esteMes;

  bool _coincidePeriodo(DateTime fecha) {
    final ahora = DateTime.now();
    switch (_periodo) {
      case PeriodoIngresoExtra.esteMes:
        return fecha.year == ahora.year && fecha.month == ahora.month;
      case PeriodoIngresoExtra.mesAnterior:
        final mesAnterior = DateTime(ahora.year, ahora.month - 1);
        return fecha.year == mesAnterior.year && fecha.month == mesAnterior.month;
      case PeriodoIngresoExtra.todos:
        return true;
    }
  }

  List<IngresoExtraModel> _aplicarFiltros(List<IngresoExtraModel> ingresos) {
    return ingresos.where((i) => _coincidePeriodo(i.fecha)).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
  }

  void _abrirFormulario({IngresoExtraModel? ingreso}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => IngresoExtraFormSheet(ingreso: ingreso),
    );
  }

  Future<void> _eliminar(IngresoExtraModel ingreso) async {
    final provider = context.read<IngresoExtraProvider>();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar ingreso'),
        content: Text(
          '¿Eliminar "${ingreso.concepto}" (${_formatoMonto(ingreso.monto, ingreso.moneda)})? '
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
      await provider.eliminar(ingreso.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingreso eliminado')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IngresoExtraProvider>();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Otros Ingresos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<PeriodoIngresoExtra>(
                segments: PeriodoIngresoExtra.values
                    .map((p) => ButtonSegment(value: p, label: Text(p.label)))
                    .toList(),
                selected: {_periodo},
                onSelectionChanged: (seleccion) => setState(() => _periodo = seleccion.first),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<IngresoExtraModel>>(
        stream: provider.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar los ingresos: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final ingresos = _aplicarFiltros(snapshot.data!);
          final totalArs = ingresos
              .where((i) => i.moneda == MonedaGasto.ars)
              .fold<double>(0, (s, i) => s + i.monto);
          final totalUsd = ingresos
              .where((i) => i.moneda == MonedaGasto.usd)
              .fold<double>(0, (s, i) => s + i.monto);

          return Column(
            children: [
              _ResumenIngresosBanner(
                periodo: _periodo.label,
                totalArs: totalArs,
                totalUsd: totalUsd,
              ),
              Expanded(
                child: ingresos.isEmpty
                    ? const Center(child: Text('No hay ingresos registrados en este filtro'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        itemCount: ingresos.length,
                        itemBuilder: (context, i) {
                          final item = ingresos[i];
                          return _IngresoExtraCard(
                            ingreso: item,
                            onEditar: () => _abrirFormulario(ingreso: item),
                            onEliminar: () => _eliminar(item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// BANNER DE RESUMEN
/// -----------------------------------------------------------------------

class _ResumenIngresosBanner extends StatelessWidget {
  final String periodo;
  final double totalArs;
  final double totalUsd;

  const _ResumenIngresosBanner({
    required this.periodo,
    required this.totalArs,
    required this.totalUsd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = _colorIngresoExtra;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.trending_up, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total cobrado · $periodo', style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Text(
                      _formatoArs.format(totalArs),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800, color: color),
                    ),
                    if (totalUsd > 0)
                      Text(
                        '+ ${_formatoUsd.format(totalUsd)}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700, color: color),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// TARJETA DE INGRESO
/// -----------------------------------------------------------------------

class _IngresoExtraCard extends StatelessWidget {
  final IngresoExtraModel ingreso;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _IngresoExtraCard({required this.ingreso, required this.onEditar, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            Container(width: 5, color: _colorIngresoExtra),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ingreso.concepto,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatoFecha.format(ingreso.fecha),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatoMonto(ingreso.monto, ingreso.moneda),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _colorIngresoExtra,
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (accion) {
                            if (accion == 'editar') onEditar();
                            if (accion == 'eliminar') onEliminar();
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
                            PopupMenuItem(
                              value: 'eliminar',
                              child: ListTile(
                                leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                                title: Text('Eliminar',
                                    style: TextStyle(color: theme.colorScheme.error)),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _Badge(
                      icon: ingreso.medioPago.icon,
                      label: ingreso.medioPago.label,
                      color: ingreso.medioPago.color,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// FORMULARIO: NUEVO / EDITAR INGRESO
/// -----------------------------------------------------------------------

/// Es público para poder abrirse como modal directo desde el Dashboard
/// (acceso rápido "Agregar Ingreso") sin tener que navegar primero a
/// [IngresosExtraScreen].
class IngresoExtraFormSheet extends StatefulWidget {
  final IngresoExtraModel? ingreso;
  const IngresoExtraFormSheet({super.key, this.ingreso});

  @override
  State<IngresoExtraFormSheet> createState() => IngresoExtraFormSheetState();
}

class IngresoExtraFormSheetState extends State<IngresoExtraFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _conceptoCtrl = TextEditingController(text: widget.ingreso?.concepto ?? '');
  late final _montoCtrl =
      TextEditingController(text: widget.ingreso?.monto.toStringAsFixed(0) ?? '');

  late MonedaGasto _moneda = widget.ingreso?.moneda ?? MonedaGasto.ars;
  late MedioPago _medioPago = widget.ingreso?.medioPago ?? MedioPago.efectivo;
  late DateTime _fecha = widget.ingreso?.fecha ?? DateTime.now();
  bool _guardando = false;

  bool get _esEdicion => widget.ingreso != null;

  @override
  void dispose() {
    _conceptoCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  String? _validarRequerido(String? value, {String campo = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) return '$campo es obligatorio';
    return null;
  }

  String? _validarMonto(String? value) {
    if (value == null || value.trim().isEmpty) return 'El monto es obligatorio';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número válido';
    if (n <= 0) return 'Debe ser mayor a 0';
    return null;
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final ingreso = IngresoExtraModel(
      id: widget.ingreso?.id ?? '',
      concepto: _conceptoCtrl.text.trim(),
      monto: double.parse(_montoCtrl.text.trim().replaceAll(',', '.')),
      moneda: _moneda,
      fecha: _fecha,
      medioPago: _medioPago,
    );

    try {
      final provider = context.read<IngresoExtraProvider>();
      if (_esEdicion) {
        await provider.actualizar(ingreso);
      } else {
        await provider.agregar(ingreso);
      }
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_esEdicion ? 'Ingreso actualizado' : 'Ingreso registrado')),
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

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
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
                  _esEdicion ? 'Editar ingreso' : 'Nuevo ingreso',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Reparaciones, arreglos u otros servicios (no venta de equipos)',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _conceptoCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    hintText: 'Ej: Cambio de pantalla iPhone 11',
                  ),
                  validator: (v) => _validarRequerido(v, campo: 'El concepto'),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _montoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Monto'),
                        validator: _validarMonto,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<MonedaGasto>(
                        initialValue: _moneda,
                        decoration: const InputDecoration(labelText: 'Moneda'),
                        items: MonedaGasto.values
                            .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _moneda = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _elegirFecha,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Fecha'),
                    child: Text(_formatoFecha.format(_fecha)),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Medio de pago', style: Theme.of(context).textTheme.bodySmall),
                ),
                const SizedBox(height: 6),
                SegmentedButton<MedioPago>(
                  segments: [
                    ButtonSegment(
                      value: MedioPago.efectivo,
                      label: Text(MedioPago.efectivo.label),
                      icon: Icon(MedioPago.efectivo.icon),
                    ),
                    ButtonSegment(
                      value: MedioPago.transferencia,
                      label: Text(MedioPago.transferencia.label),
                      icon: Icon(MedioPago.transferencia.icon),
                    ),
                  ],
                  selected: {_medioPago},
                  onSelectionChanged: (seleccion) => setState(() => _medioPago = seleccion.first),
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
                        : Text(_esEdicion ? 'Guardar cambios' : 'Guardar ingreso'),
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
