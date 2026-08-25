import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show StockEmpresaProvider, AppDrawer;
import '../models/stock_empresa_model.dart';

/// Categorías fijas para clasificar accesorios, repuestos e insumos.
const List<String> kCategoriasStockEmpresa = [
  'Cargadores',
  'Fundas',
  'Vidrios Templados',
  'Repuestos',
  'Otros',
];

const String _tabTodos = 'Todos';

/// -----------------------------------------------------------------------
/// PANTALLA: STOCK DE EMPRESA (accesorios, repuestos e insumos)
/// -----------------------------------------------------------------------

class StockEmpresaScreen extends StatefulWidget {
  const StockEmpresaScreen({super.key});

  @override
  State<StockEmpresaScreen> createState() => _StockEmpresaScreenState();
}

class _StockEmpresaScreenState extends State<StockEmpresaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<String> _tabs = [_tabTodos, ...kCategoriasStockEmpresa];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      // Repinta la lista cuando cambia la pestaña seleccionada.
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<StockEmpresaModel> _filtrarPorCategoria(List<StockEmpresaModel> items) {
    final categoria = _tabs[_tabController.index];
    if (categoria == _tabTodos) return items;
    return items.where((e) => e.categoria == categoria).toList();
  }

  Future<void> _ajustarCantidad(StockEmpresaModel item, int delta) async {
    final provider = context.read<StockEmpresaProvider>();
    final nuevaCantidad = item.cantidad + delta;
    if (nuevaCantidad < 0) return;
    await provider.actualizar(item.copyWith(cantidad: nuevaCantidad));
  }

  void _abrirFormularioNuevoProducto() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _StockEmpresaFormSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StockEmpresaProvider>();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Stock de Empresa'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: StreamBuilder<List<StockEmpresaModel>>(
        stream: provider.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar el stock: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = _filtrarPorCategoria(snapshot.data!);

          if (items.isEmpty) {
            return const Center(child: Text('No hay productos en esta categoría'));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final e = items[i];
              return _StockEmpresaCard(
                item: e,
                onIncrementar: () => _ajustarCantidad(e, 1),
                onDecrementar: () => _ajustarCantidad(e, -1),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormularioNuevoProducto,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// TARJETA DE PRODUCTO
/// -----------------------------------------------------------------------

class _StockEmpresaCard extends StatelessWidget {
  final StockEmpresaModel item;
  final VoidCallback onIncrementar;
  final VoidCallback onDecrementar;

  const _StockEmpresaCard({
    required this.item,
    required this.onIncrementar,
    required this.onDecrementar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stockBajo = item.stockBajo();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                        item.nombre,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(item.categoria, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (stockBajo) const _StockBajoBadge(),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.attach_money,
                  label: 'Costo \$${item.costoUnitario.toStringAsFixed(0)}',
                ),
                _InfoChip(
                  icon: Icons.price_check,
                  label: 'Venta \$${item.precioVenta.toStringAsFixed(0)}',
                ),
                _InfoChip(
                  icon: Icons.trending_up,
                  label: 'Ganancia \$${item.gananciaUnitaria.toStringAsFixed(0)}/u',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Cantidad en stock', style: theme.textTheme.bodyMedium),
                Row(
                  children: [
                    _CantidadBoton(
                      icon: Icons.remove,
                      onPressed: item.cantidad > 0 ? onDecrementar : null,
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${item.cantidad}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _CantidadBoton(icon: Icons.add, onPressed: onIncrementar),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CantidadBoton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _CantidadBoton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _StockBajoBadge extends StatelessWidget {
  const _StockBajoBadge();

  @override
  Widget build(BuildContext context) {
    const color = Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: const Text(
        'Stock bajo',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// FORMULARIO: NUEVO PRODUCTO
/// -----------------------------------------------------------------------

class _StockEmpresaFormSheet extends StatefulWidget {
  const _StockEmpresaFormSheet();

  @override
  State<_StockEmpresaFormSheet> createState() => _StockEmpresaFormSheetState();
}

class _StockEmpresaFormSheetState extends State<_StockEmpresaFormSheet> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '1');
  final _costoUnitarioCtrl = TextEditingController();
  final _precioVentaCtrl = TextEditingController();

  String _categoria = kCategoriasStockEmpresa.first;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cantidadCtrl.dispose();
    _costoUnitarioCtrl.dispose();
    _precioVentaCtrl.dispose();
    super.dispose();
  }

  String? _validarRequerido(String? value, {String campo = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) {
      return '$campo es obligatorio';
    }
    return null;
  }

  String? _validarEntero(String? value, {required int min, String campo = 'Valor'}) {
    if (value == null || value.trim().isEmpty) return '$campo es obligatorio';
    final n = int.tryParse(value.trim());
    if (n == null) return '$campo debe ser un número entero';
    if (n < min) return '$campo no puede ser menor a $min';
    return null;
  }

  String? _validarDecimalPositivo(String? value, {String campo = 'Valor'}) {
    if (value == null || value.trim().isEmpty) return '$campo es obligatorio';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return '$campo debe ser un número válido';
    if (n < 0) return '$campo no puede ser negativo';
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final nuevo = StockEmpresaModel(
      id: '',
      nombre: _nombreCtrl.text.trim(),
      categoria: _categoria,
      cantidad: int.parse(_cantidadCtrl.text.trim()),
      costoUnitario: double.parse(_costoUnitarioCtrl.text.trim().replaceAll(',', '.')),
      precioVenta: double.parse(_precioVentaCtrl.text.trim().replaceAll(',', '.')),
    );

    try {
      await context.read<StockEmpresaProvider>().agregar(nuevo);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto agregado al stock')),
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
                  'Nuevo producto',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText: 'Ej: Funda transparente iPhone 13',
                  ),
                  validator: (v) => _validarRequerido(v, campo: 'El nombre'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: kCategoriasStockEmpresa
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _categoria = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cantidadCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cantidad inicial'),
                  validator: (v) => _validarEntero(v, min: 0, campo: 'La cantidad'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _costoUnitarioCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Precio de costo',
                          prefixText: '\$ ',
                        ),
                        validator: (v) => _validarDecimalPositivo(v, campo: 'El costo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _precioVentaCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Precio de venta',
                          prefixText: '\$ ',
                        ),
                        validator: (v) => _validarDecimalPositivo(v, campo: 'El precio de venta'),
                      ),
                    ),
                  ],
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
                        : const Text('Guardar producto'),
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
