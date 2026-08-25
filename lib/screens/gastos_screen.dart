import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../main.dart' show AppDrawer, GastoProvider;
import '../models/gasto_model.dart';

final _formatoArs = NumberFormat.currency(locale: 'es_AR', symbol: 'AR\$', decimalDigits: 0);
final _formatoUsd = NumberFormat.currency(locale: 'en_US', symbol: 'USD \$', decimalDigits: 0);
final _formatoFecha = DateFormat('dd/MM/yyyy');

String _formatoMonto(double monto, MonedaGasto moneda) {
  return moneda == MonedaGasto.usd ? _formatoUsd.format(monto) : _formatoArs.format(monto);
}

/// Período rápido para filtrar la lista de gastos.
enum PeriodoGasto { esteMes, mesAnterior, todos }

extension _PeriodoGastoExtension on PeriodoGasto {
  String get label {
    switch (this) {
      case PeriodoGasto.esteMes:
        return 'Este mes';
      case PeriodoGasto.mesAnterior:
        return 'Mes anterior';
      case PeriodoGasto.todos:
        return 'Todos';
    }
  }
}

/// Color e ícono según la categoría, solo para uso visual de esta pantalla.
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

  IconData get icon {
    switch (this) {
      case CategoriaGasto.alquiler:
        return Icons.home_outlined;
      case CategoriaGasto.insumos:
        return Icons.inventory_2_outlined;
      case CategoriaGasto.servicios:
        return Icons.bolt_outlined;
      case CategoriaGasto.importacion:
        return Icons.local_shipping_outlined;
      case CategoriaGasto.personal:
        return Icons.people_outline;
      case CategoriaGasto.varios:
        return Icons.category_outlined;
    }
  }
}

/// Color e ícono según el medio de pago, solo para uso visual.
extension _MedioPagoUi on MedioPago {
  Color get color => this == MedioPago.transferencia ? Colors.blue : Colors.green;

  IconData get icon =>
      this == MedioPago.transferencia ? Icons.account_balance : Icons.payments;
}

/// -----------------------------------------------------------------------
/// PANTALLA: GASTOS
/// -----------------------------------------------------------------------

class GastosScreen extends StatefulWidget {
  const GastosScreen({super.key});

  @override
  State<GastosScreen> createState() => _GastosScreenState();
}

class _GastosScreenState extends State<GastosScreen> {
  CategoriaGasto? _categoriaFiltro;
  PeriodoGasto _periodo = PeriodoGasto.esteMes;

  bool _coincidePeriodo(DateTime fecha) {
    final ahora = DateTime.now();
    switch (_periodo) {
      case PeriodoGasto.esteMes:
        return fecha.year == ahora.year && fecha.month == ahora.month;
      case PeriodoGasto.mesAnterior:
        final mesAnterior = DateTime(ahora.year, ahora.month - 1);
        return fecha.year == mesAnterior.year && fecha.month == mesAnterior.month;
      case PeriodoGasto.todos:
        return true;
    }
  }

  List<GastoModel> _aplicarFiltros(List<GastoModel> gastos) {
    return gastos.where((g) {
      final coincideCategoria = _categoriaFiltro == null || g.categoria == _categoriaFiltro;
      return coincideCategoria && _coincidePeriodo(g.fecha);
    }).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
  }

  void _abrirFormulario({GastoModel? gasto}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => GastoFormSheet(gasto: gasto),
    );
  }

  Future<void> _eliminar(GastoModel gasto) async {
    final provider = context.read<GastoProvider>();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar gasto'),
        content: Text(
          '¿Eliminar "${gasto.descripcion}" (${_formatoMonto(gasto.monto, gasto.moneda)})? '
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
      await provider.eliminar(gasto.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gasto eliminado')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GastoProvider>();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Gastos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: _categoriaFiltro == null,
                        onSelected: (_) => setState(() => _categoriaFiltro = null),
                      ),
                      const SizedBox(width: 8),
                      ...CategoriaGasto.values.map((c) {
                        final seleccionada = _categoriaFiltro == c;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(c.icon, size: 15),
                            label: Text(c.label),
                            selected: seleccionada,
                            onSelected: (_) => setState(() => _categoriaFiltro = c),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<PeriodoGasto>(
                    segments: PeriodoGasto.values
                        .map((p) => ButtonSegment(value: p, label: Text(p.label)))
                        .toList(),
                    selected: {_periodo},
                    onSelectionChanged: (seleccion) =>
                        setState(() => _periodo = seleccion.first),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<GastoModel>>(
        stream: provider.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar los gastos: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final gastos = _aplicarFiltros(snapshot.data!);
          final totalArs = gastos
              .where((g) => g.moneda == MonedaGasto.ars)
              .fold<double>(0, (s, g) => s + g.monto);
          final totalUsd = gastos
              .where((g) => g.moneda == MonedaGasto.usd)
              .fold<double>(0, (s, g) => s + g.monto);

          return Column(
            children: [
              _ResumenGastosBanner(
                periodo: _periodo.label,
                totalArs: totalArs,
                totalUsd: totalUsd,
              ),
              Expanded(
                child: gastos.isEmpty
                    ? const Center(child: Text('No hay gastos registrados en este filtro'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        itemCount: gastos.length,
                        itemBuilder: (context, i) {
                          final g = gastos[i];
                          return _GastoCard(
                            gasto: g,
                            onEditar: () => _abrirFormulario(gasto: g),
                            onEliminar: () => _eliminar(g),
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

class _ResumenGastosBanner extends StatelessWidget {
  final String periodo;
  final double totalArs;
  final double totalUsd;

  const _ResumenGastosBanner({
    required this.periodo,
    required this.totalArs,
    required this.totalUsd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = Colors.red;

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
            decoration: const BoxDecoration(color: Color(0x1AFF3B30), shape: BoxShape.circle),
            child: const Icon(Icons.trending_down, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total gastado · $periodo', style: theme.textTheme.bodySmall),
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
/// TARJETA DE GASTO
/// -----------------------------------------------------------------------

class _GastoCard extends StatelessWidget {
  final GastoModel gasto;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _GastoCard({required this.gasto, required this.onEditar, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorCategoria = gasto.categoria.color;

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
            Container(width: 5, color: colorCategoria),
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
                                gasto.descripcion,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatoFecha.format(gasto.fecha),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatoMonto(gasto.monto, gasto.moneda),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.red,
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Badge(
                          icon: gasto.categoria.icon,
                          label: gasto.categoria.label,
                          color: colorCategoria,
                        ),
                        _Badge(
                          icon: gasto.medioPago.icon,
                          label: gasto.medioPago.label,
                          color: gasto.medioPago.color,
                        ),
                      ],
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
/// FORMULARIO: NUEVO / EDITAR GASTO
/// -----------------------------------------------------------------------

class GastoFormSheet extends StatefulWidget {
  final GastoModel? gasto;
  const GastoFormSheet({super.key, this.gasto});

  @override
  State<GastoFormSheet> createState() => GastoFormSheetState();
}

class GastoFormSheetState extends State<GastoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _descripcionCtrl = TextEditingController(text: widget.gasto?.descripcion ?? '');
  late final _montoCtrl =
      TextEditingController(text: widget.gasto?.monto.toStringAsFixed(0) ?? '');

  late CategoriaGasto _categoria = widget.gasto?.categoria ?? CategoriaGasto.varios;
  late MonedaGasto _moneda = widget.gasto?.moneda ?? MonedaGasto.ars;
  late MedioPago _medioPago = widget.gasto?.medioPago ?? MedioPago.efectivo;
  late DateTime _fecha = widget.gasto?.fecha ?? DateTime.now();
  bool _guardando = false;

  bool get _esEdicion => widget.gasto != null;

  @override
  void dispose() {
    _descripcionCtrl.dispose();
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

    final gasto = GastoModel(
      id: widget.gasto?.id ?? '',
      descripcion: _descripcionCtrl.text.trim(),
      monto: double.parse(_montoCtrl.text.trim().replaceAll(',', '.')),
      moneda: _moneda,
      categoria: _categoria,
      fecha: _fecha,
      medioPago: _medioPago,
    );

    try {
      final provider = context.read<GastoProvider>();
      if (_esEdicion) {
        await provider.actualizar(gasto);
      } else {
        await provider.agregar(gasto);
      }
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_esEdicion ? 'Gasto actualizado' : 'Gasto registrado')),
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
        initialChildSize: 0.8,
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
                  _esEdicion ? 'Editar gasto' : 'Nuevo gasto',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descripcionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    hintText: 'Ej: Alquiler local Agosto',
                  ),
                  validator: (v) => _validarRequerido(v, campo: 'La descripción'),
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
                DropdownButtonFormField<CategoriaGasto>(
                  initialValue: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: CategoriaGasto.values
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _categoria = value);
                  },
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
                        : Text(_esEdicion ? 'Guardar cambios' : 'Guardar gasto'),
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
