import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../main.dart' show AndroidProvider, AppDrawer;
import '../models/android_model.dart';
import '../models/deuda_model.dart' show TipoDeuda;
import '../widgets/cotizacion_blue_field.dart';
import '../widgets/equipo_fotos_field.dart';
import 'finanzas_screen.dart' show DeudaFormSheet;

final _formatoUsd = NumberFormat.currency(locale: 'en_US', symbol: 'USD \$', decimalDigits: 0);
final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Opciones típicas para el selector de meses de garantía. Si un equipo
/// tiene un valor distinto (cargado antes de tener este selector), se agrega
/// dinámicamente a la lista para no romper el Dropdown.
const List<int> _opcionesGarantia = [0, 1, 3, 6, 12, 24];

String _labelMesesGarantia(int meses) {
  if (meses == 0) return 'Sin garantía';
  if (meses == 1) return '1 mes';
  return '$meses meses';
}

/// Sugerencias rápidas de marcas frecuentes (el campo sigue siendo texto
/// libre: el usuario puede escribir cualquier otra marca).
const List<String> _marcasSugeridas = ['Samsung', 'Motorola', 'Xiaomi'];

/// Filtro de disponibilidad / garantía para la lista de equipos.
enum FiltroDisponibilidadAndroid { todos, disponibles, vendidos, enGarantia }

extension _FiltroDisponibilidadAndroidExtension on FiltroDisponibilidadAndroid {
  String get label {
    switch (this) {
      case FiltroDisponibilidadAndroid.todos:
        return 'Todos';
      case FiltroDisponibilidadAndroid.disponibles:
        return 'Disponibles';
      case FiltroDisponibilidadAndroid.vendidos:
        return 'Vendidos';
      case FiltroDisponibilidadAndroid.enGarantia:
        return 'En Garantía';
    }
  }

  IconData get icon {
    switch (this) {
      case FiltroDisponibilidadAndroid.todos:
        return Icons.apps;
      case FiltroDisponibilidadAndroid.disponibles:
        return Icons.check_circle_outline;
      case FiltroDisponibilidadAndroid.vendidos:
        return Icons.sell_outlined;
      case FiltroDisponibilidadAndroid.enGarantia:
        return Icons.shield_outlined;
    }
  }
}

/// -----------------------------------------------------------------------
/// PANTALLA: STOCK DE ANDROID
/// -----------------------------------------------------------------------

class AndroidScreen extends StatefulWidget {
  /// Filtro con el que arranca la pantalla (ej. al llegar desde un acceso
  /// directo del dashboard).
  final FiltroDisponibilidadAndroid filtroInicial;

  /// Si es `true`, abre automáticamente el formulario de alta al entrar.
  final bool abrirFormularioAlIniciar;

  const AndroidScreen({
    super.key,
    this.filtroInicial = FiltroDisponibilidadAndroid.todos,
    this.abrirFormularioAlIniciar = false,
  });

  @override
  State<AndroidScreen> createState() => _AndroidScreenState();
}

class _AndroidScreenState extends State<AndroidScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  late FiltroDisponibilidadAndroid _filtro = widget.filtroInicial;

  @override
  void initState() {
    super.initState();
    if (widget.abrirFormularioAlIniciar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _abrirFormularioEquipo();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AndroidModel> _aplicarFiltros(List<AndroidModel> equipos) {
    final query = _query.trim().toLowerCase();

    return equipos.where((e) {
      final coincideBusqueda = query.isEmpty ||
          e.marca.toLowerCase().contains(query) ||
          e.modelo.toLowerCase().contains(query) ||
          (e.imei?.toLowerCase().contains(query) ?? false);

      final garantia = e.tiempoGarantiaRestante;
      final coincideFiltro = switch (_filtro) {
        FiltroDisponibilidadAndroid.todos => true,
        FiltroDisponibilidadAndroid.disponibles => !e.vendido,
        FiltroDisponibilidadAndroid.vendidos => e.vendido,
        FiltroDisponibilidadAndroid.enGarantia =>
          e.vendido && garantia != null && !garantia.vencida,
      };

      return coincideBusqueda && coincideFiltro;
    }).toList();
  }

  /// Abre el modal obligatorio de venta (precio definitivo, fecha, garantía
  /// y teléfono del comprador) y aplica los cambios al confirmar.
  Future<void> _marcarVendido(AndroidModel equipo) async {
    final provider = context.read<AndroidProvider>();
    final resultado = await showDialog<_VentaConfirmadaAndroid>(
      context: context,
      builder: (context) => _MarcarVendidoDialogAndroid(equipo: equipo),
    );

    if (resultado != null) {
      final telefono = resultado.telefono?.trim();
      await provider.actualizar(equipo.copyWith(
        vendido: true,
        precioVenta: resultado.precioVenta,
        fechaVenta: resultado.fecha,
        mesesGarantia: resultado.mesesGarantia,
        telefonoCliente: (telefono == null || telefono.isEmpty) ? null : telefono,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Equipo marcado como vendido')),
        );
      }

      // Venta financiada (en cuotas): mismo flujo que en iphones_screen.dart
      // -ver el comentario allá para el detalle de por qué se vincula la
      // cuenta al equipo en vez de reconocer todo el ingreso de una vez.
      if (resultado.financiada && mounted) {
        // El monto NO se prellena: ver el comentario en iphones_screen.dart
        // -el precio de venta del equipo está en USD, pero las cuentas de
        // Finanzas siempre están en pesos-.
        final cuentaVinculada = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => DeudaFormSheet(
            tipoInicial: TipoDeuda.deudor,
            conceptoInicial:
                'Venta financiada - ${equipo.marca} ${equipo.modelo} ${equipo.almacenamiento}',
            fechaInicial: resultado.fecha,
            idEquipoVinculado: equipo.id,
            tipoEquipoVinculado: 'android',
          ),
        );
        if (cuentaVinculada != true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'El equipo quedó vendido sin cuenta vinculada. Podés vincularla '
                'después desde Finanzas → editar la cuenta → "¿Corresponde a la '
                'venta de un equipo?".',
              ),
              duration: Duration(seconds: 6),
            ),
          );
        }
      }
    }
  }

  Future<void> _eliminarEquipo(AndroidModel equipo) async {
    final provider = context.read<AndroidProvider>();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar equipo'),
        content: Text(
          '¿Eliminar "${equipo.marca} ${equipo.modelo}" del stock? '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await provider.eliminar(equipo.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Equipo eliminado del stock')),
        );
      }
    }
  }

  void _abrirFormularioEquipo({AndroidModel? equipo}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AndroidFormSheet(equipo: equipo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AndroidProvider>();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Stock de Android'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar por marca, modelo o IMEI',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: FiltroDisponibilidadAndroid.values.length,
                    separatorBuilder: (context, i) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final f = FiltroDisponibilidadAndroid.values[i];
                      final seleccionado = _filtro == f;
                      return ChoiceChip(
                        avatar: Icon(f.icon, size: 16),
                        label: Text(f.label),
                        selected: seleccionado,
                        onSelected: (_) => setState(() => _filtro = f),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<AndroidModel>>(
        stream: provider.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar el stock: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final equipos = _aplicarFiltros(snapshot.data!);

          if (equipos.isEmpty) {
            return const Center(child: Text('No se encontraron equipos'));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: equipos.length,
            itemBuilder: (context, i) {
              final e = equipos[i];
              return _AndroidCard(
                equipo: e,
                onMarcarVendido: () => _marcarVendido(e),
                onEditar: () => _abrirFormularioEquipo(equipo: e),
                onEliminar: () => _eliminarEquipo(e),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormularioEquipo(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// TARJETA DE EQUIPO
/// -----------------------------------------------------------------------

class _AndroidCard extends StatelessWidget {
  final AndroidModel equipo;
  final VoidCallback onMarcarVendido;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _AndroidCard({
    required this.equipo,
    required this.onMarcarVendido,
    required this.onEditar,
    required this.onEliminar,
  });

  Color _colorAcento(BuildContext context) {
    if (!equipo.vendido) return Colors.green;
    final garantia = equipo.tiempoGarantiaRestante;
    if (garantia != null && !garantia.vencida) return Colors.blue;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final porcentajePropio = equipo.porcentajeSocio == null
        ? null
        : (100 - equipo.porcentajeSocio!);
    final garantia = equipo.tiempoGarantiaRestante;
    final gananciaNeta = equipo.gananciaPropia;

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
            Container(width: 5, color: _colorAcento(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
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
                                '${equipo.marca} ${equipo.modelo}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${equipo.almacenamiento} · ${equipo.ram} RAM · ${equipo.color}'
                                '${equipo.imei != null && equipo.imei!.isNotEmpty ? " · IMEI ${equipo.imei}" : ""}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
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
                                title: Text('Eliminar', style: TextStyle(color: theme.colorScheme.error)),
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
                        _EstadoBadgeAndroid(vendido: equipo.vendido),
                        if (equipo.vendido && garantia != null)
                          _GarantiaBadgeAndroid(garantia: garantia),
                        _InfoChipAndroid(icon: Icons.sell_outlined, label: equipo.estado.label),
                        if (equipo.imei != null && equipo.imei!.isNotEmpty)
                          _ImeiBadgeAndroid(imei: equipo.imei!),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChipAndroid(
                          icon: Icons.attach_money,
                          label: 'Costo ${_formatoUsd.format(equipo.costo)}',
                        ),
                        if (equipo.precioVenta != null)
                          _InfoChipAndroid(
                            icon: Icons.price_check,
                            label: 'Venta ${_formatoUsd.format(equipo.precioVenta!)}',
                          )
                        else
                          _InfoChipAndroid(
                            icon: Icons.help_outline,
                            label: 'Precio a definir',
                          ),
                        if (equipo.vendido && gananciaNeta != null)
                          _GananciaBadgeAndroid(monto: gananciaNeta),
                      ],
                    ),
                    if (equipo.esCompartido) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.handshake_outlined,
                                size: 18, color: theme.colorScheme.onTertiaryContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Compartido con ${equipo.nombreSocio ?? "socio"} · '
                                '${porcentajePropio?.toStringAsFixed(0) ?? "-"}/'
                                '${equipo.porcentajeSocio?.toStringAsFixed(0) ?? "-"}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onTertiaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (equipo.vendido) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Vendido el ${equipo.fechaVenta != null ? _formatoFecha.format(equipo.fechaVenta!) : "-"}'
                        '${equipo.telefonoCliente != null && equipo.telefonoCliente!.isNotEmpty ? " · Tel: ${equipo.telefonoCliente}" : ""}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (!equipo.vendido)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onMarcarVendido,
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Marcar como vendido'),
                        ),
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

class _EstadoBadgeAndroid extends StatelessWidget {
  final bool vendido;
  const _EstadoBadgeAndroid({required this.vendido});

  @override
  Widget build(BuildContext context) {
    final color = vendido ? Colors.red : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        vendido ? 'Vendido' : 'Disponible',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _GarantiaBadgeAndroid extends StatelessWidget {
  final TiempoGarantiaRestanteAndroid garantia;
  const _GarantiaBadgeAndroid({required this.garantia});

  @override
  Widget build(BuildContext context) {
    final color = garantia.vencida ? Colors.grey : Colors.blue;
    final label = garantia.vencida ? 'Garantía vencida' : 'En garantía · ${garantia.descripcion}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Badge que destaca el IMEI del equipo, cuando está cargado.
class _ImeiBadgeAndroid extends StatelessWidget {
  final String imei;
  const _ImeiBadgeAndroid({required this.imei});

  @override
  Widget build(BuildContext context) {
    const color = Colors.deepPurple;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pin_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            'IMEI $imei',
            style: const TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Badge que muestra la ganancia neta (USD) de un equipo ya vendido.
class _GananciaBadgeAndroid extends StatelessWidget {
  final double monto;
  const _GananciaBadgeAndroid({required this.monto});

  @override
  Widget build(BuildContext context) {
    const color = Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            'Ganancia neta ${_formatoUsd.format(monto)}',
            style: const TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoChipAndroid extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChipAndroid({required this.icon, required this.label});

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
/// DIÁLOGO: MARCAR COMO VENDIDO
/// -----------------------------------------------------------------------

class _VentaConfirmadaAndroid {
  final double precioVenta;
  final DateTime fecha;
  final int mesesGarantia;
  final String? telefono;
  final bool financiada;

  const _VentaConfirmadaAndroid({
    required this.precioVenta,
    required this.fecha,
    required this.mesesGarantia,
    this.telefono,
    required this.financiada,
  });
}

class _MarcarVendidoDialogAndroid extends StatefulWidget {
  final AndroidModel equipo;
  const _MarcarVendidoDialogAndroid({required this.equipo});

  @override
  State<_MarcarVendidoDialogAndroid> createState() => _MarcarVendidoDialogAndroidState();
}

class _MarcarVendidoDialogAndroidState extends State<_MarcarVendidoDialogAndroid> {
  final _formKey = GlobalKey<FormState>();
  late final _precioVentaCtrl = TextEditingController(
    text: widget.equipo.precioVenta?.toStringAsFixed(0) ?? '',
  );
  final _precioVentaPesosCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  late int _mesesGarantia = widget.equipo.mesesGarantia;
  bool _financiada = false;

  /// Ver el comentario en iphones_screen.dart -mismo mecanismo de carga en
  /// pesos convertida sola a USD con el dólar blue-.
  bool _precioEnPesos = false;
  double? _tasaBlue;

  @override
  void dispose() {
    _precioVentaCtrl.dispose();
    _precioVentaPesosCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
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

  String? _validarPrecioVenta(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresá el precio de venta definitivo';
    }
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número válido';
    if (n <= 0) return 'Debe ser mayor a 0';
    return null;
  }

  String? _validarPrecioVentaPesos(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresá el precio de venta en pesos';
    }
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número válido';
    if (n <= 0) return 'Debe ser mayor a 0';
    return null;
  }

  void _confirmar() {
    if (!_formKey.currentState!.validate()) return;
    if (_precioEnPesos && (_tasaBlue == null || _tasaBlue! <= 0)) return;

    final precio = _precioEnPesos
        ? double.parse(_precioVentaPesosCtrl.text.trim().replaceAll(',', '.')) / _tasaBlue!
        : double.parse(_precioVentaCtrl.text.trim().replaceAll(',', '.'));

    Navigator.of(context).pop(
      _VentaConfirmadaAndroid(
        precioVenta: precio,
        fecha: _fecha,
        mesesGarantia: _mesesGarantia,
        telefono: _telefonoCtrl.text.trim(),
        financiada: _financiada,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final equipo = widget.equipo;
    final opcionesGarantia = <int>{..._opcionesGarantia, _mesesGarantia}.toList()..sort();

    return AlertDialog(
      title: const Text('Marcar como vendido'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${equipo.marca} ${equipo.modelo} · ${equipo.almacenamiento}'),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Cargar en USD')),
                  ButtonSegment(value: true, label: Text('Cargar en pesos')),
                ],
                selected: {_precioEnPesos},
                onSelectionChanged: (seleccion) =>
                    setState(() => _precioEnPesos = seleccion.first),
              ),
              const SizedBox(height: 12),
              if (_precioEnPesos) ...[
                TextFormField(
                  controller: _precioVentaPesosCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio de venta (en pesos)',
                    prefixText: '\$ ',
                  ),
                  validator: _validarPrecioVentaPesos,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                CotizacionBlueField(onTasaResuelta: (tasa) => setState(() => _tasaBlue = tasa)),
                if (_tasaBlue != null && _precioVentaPesosCtrl.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Builder(builder: (context) {
                      final pesos =
                          double.tryParse(_precioVentaPesosCtrl.text.trim().replaceAll(',', '.'));
                      if (pesos == null) return const SizedBox.shrink();
                      return Text(
                        'Equivale a USD \$${(pesos / _tasaBlue!).toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    }),
                  ),
              ] else
                TextFormField(
                  controller: _precioVentaCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio de venta definitivo',
                    prefixText: 'USD \$ ',
                  ),
                  validator: _validarPrecioVenta,
                ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _elegirFecha,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha de venta',
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(_formatoFecha.format(_fecha)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _mesesGarantia,
                decoration: const InputDecoration(labelText: 'Garantía'),
                items: opcionesGarantia
                    .map((m) => DropdownMenuItem(value: m, child: Text(_labelMesesGarantia(m))))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _mesesGarantia = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono del comprador (opcional)',
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Venta financiada (en cuotas)'),
                subtitle: const Text(
                  'Se crea la cuenta en Finanzas (en pesos, la cargás en el '
                  'siguiente paso) y el balance solo cuenta la ganancia a '
                  'medida que se cobra cada cuota',
                ),
                value: _financiada,
                onChanged: (value) => setState(() => _financiada = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// FORMULARIO: NUEVO / EDITAR ANDROID
/// -----------------------------------------------------------------------

/// Formulario de alta/edición de un equipo Android. Es público para poder
/// abrirse como modal directo desde el Dashboard (acceso rápido "Nuevo
/// Android") sin tener que navegar primero a [AndroidScreen].
class AndroidFormSheet extends StatefulWidget {
  final AndroidModel? equipo;
  const AndroidFormSheet({super.key, this.equipo});

  @override
  State<AndroidFormSheet> createState() => AndroidFormSheetState();
}

class AndroidFormSheetState extends State<AndroidFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final _marcaCtrl = TextEditingController(text: widget.equipo?.marca ?? '');
  late final _modeloCtrl = TextEditingController(text: widget.equipo?.modelo ?? '');
  late final _imeiCtrl = TextEditingController(text: widget.equipo?.imei ?? '');
  late final _almacenamientoCtrl =
      TextEditingController(text: widget.equipo?.almacenamiento ?? '');
  late final _ramCtrl = TextEditingController(text: widget.equipo?.ram ?? '');
  late final _colorCtrl = TextEditingController(text: widget.equipo?.color ?? '');
  late final _costoCtrl =
      TextEditingController(text: widget.equipo?.costo.toStringAsFixed(0) ?? '');
  late final _precioVentaCtrl =
      TextEditingController(text: widget.equipo?.precioVenta?.toStringAsFixed(0) ?? '');
  late final _nombreSocioCtrl = TextEditingController(text: widget.equipo?.nombreSocio ?? '');
  late final _porcentajeSocioCtrl =
      TextEditingController(text: widget.equipo?.porcentajeSocio?.toStringAsFixed(0) ?? '');

  late List<String> _fotos = List.of(widget.equipo?.fotos ?? const []);
  final String _carpetaFotos = const Uuid().v4();

  late EstadoAndroid _estado = widget.equipo?.estado ?? EstadoAndroid.usado;
  late bool _esCompartido = widget.equipo?.esCompartido ?? false;
  late int _mesesGarantia = widget.equipo?.mesesGarantia ?? 3;
  bool _guardando = false;

  bool get _esEdicion => widget.equipo != null;

  @override
  void dispose() {
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _imeiCtrl.dispose();
    _almacenamientoCtrl.dispose();
    _ramCtrl.dispose();
    _colorCtrl.dispose();
    _costoCtrl.dispose();
    _precioVentaCtrl.dispose();
    _nombreSocioCtrl.dispose();
    _porcentajeSocioCtrl.dispose();
    super.dispose();
  }

  String? _validarRequerido(String? value, {String campo = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) {
      return '$campo es obligatorio';
    }
    return null;
  }

  /// El IMEI es opcional (no todos los equipos cargados tienen que ser
  /// celulares con IMEI disponible), pero si se completa debe tener
  /// exactamente 15 dígitos numéricos.
  String? _validarImei(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final imei = value.trim();
    if (!RegExp(r'^\d{15}$').hasMatch(imei)) {
      return 'El IMEI debe tener 15 dígitos numéricos';
    }
    return null;
  }

  String? _validarDecimalPositivo(String? value, {String campo = 'Valor'}) {
    if (value == null || value.trim().isEmpty) return '$campo es obligatorio';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return '$campo debe ser un número válido';
    if (n < 0) return '$campo no puede ser negativo';
    return null;
  }

  /// A diferencia del costo, el precio de venta es opcional al cargar el
  /// equipo: si se completa debe ser válido, pero puede dejarse vacío y
  /// definirse recién al marcar el equipo como vendido.
  String? _validarDecimalOpcional(String? value, {String campo = 'Valor'}) {
    if (value == null || value.trim().isEmpty) return null;
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return '$campo debe ser un número válido';
    if (n < 0) return '$campo no puede ser negativo';
    return null;
  }

  String? _validarPorcentajeSocio(String? value) {
    if (!_esCompartido) return null;
    if (value == null || value.trim().isEmpty) return 'Indicá el % del socio';
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número válido';
    if (n <= 0 || n >= 100) return 'Debe estar entre 1 y 99';
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final base = widget.equipo;
    final precioVentaTexto = _precioVentaCtrl.text.trim();
    final imeiTexto = _imeiCtrl.text.trim();
    final modelo = AndroidModel(
      id: base?.id ?? '',
      marca: _marcaCtrl.text.trim(),
      modelo: _modeloCtrl.text.trim(),
      imei: imeiTexto.isEmpty ? null : imeiTexto,
      almacenamiento: _almacenamientoCtrl.text.trim(),
      ram: _ramCtrl.text.trim(),
      color: _colorCtrl.text.trim(),
      estado: _estado,
      costo: double.parse(_costoCtrl.text.trim().replaceAll(',', '.')),
      precioVenta:
          precioVentaTexto.isEmpty ? null : double.parse(precioVentaTexto.replaceAll(',', '.')),
      esCompartido: _esCompartido,
      nombreSocio: _esCompartido ? _nombreSocioCtrl.text.trim() : null,
      porcentajeSocio: _esCompartido
          ? double.parse(_porcentajeSocioCtrl.text.trim().replaceAll(',', '.'))
          : null,
      // El estado de venta se gestiona desde "Marcar como vendido", no desde este formulario.
      vendido: base?.vendido ?? false,
      fechaVenta: base?.fechaVenta,
      telefonoCliente: base?.telefonoCliente,
      mesesGarantia: _mesesGarantia,
      fotos: _fotos,
    );

    try {
      final provider = context.read<AndroidProvider>();
      if (_esEdicion) {
        await provider.actualizar(modelo);
      } else {
        await provider.agregar(modelo);
      }
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_esEdicion ? 'Equipo actualizado' : 'Equipo agregado al stock')),
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
    final opcionesGarantia = <int>{..._opcionesGarantia, _mesesGarantia}.toList()..sort();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
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
                  _esEdicion ? 'Editar equipo Android' : 'Nuevo equipo Android',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _marcaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Marca',
                    hintText: 'Ej: Samsung, Motorola, Xiaomi...',
                  ),
                  validator: (v) => _validarRequerido(v, campo: 'La marca'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _marcasSugeridas
                      .map((m) => ActionChip(
                            label: Text(m),
                            onPressed: () => setState(() => _marcaCtrl.text = m),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _modeloCtrl,
                  decoration: const InputDecoration(labelText: 'Modelo', hintText: 'Ej: Galaxy S23'),
                  validator: (v) => _validarRequerido(v, campo: 'El modelo'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imeiCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'IMEI (opcional)',
                    hintText: '15 dígitos',
                  ),
                  validator: _validarImei,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _almacenamientoCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Almacenamiento', hintText: 'Ej: 128GB'),
                        validator: (v) => _validarRequerido(v, campo: 'El almacenamiento'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ramCtrl,
                        decoration: const InputDecoration(labelText: 'RAM', hintText: 'Ej: 8GB'),
                        validator: (v) => _validarRequerido(v, campo: 'La RAM'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _colorCtrl,
                        decoration: const InputDecoration(labelText: 'Color'),
                        validator: (v) => _validarRequerido(v, campo: 'El color'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<EstadoAndroid>(
                        initialValue: _estado,
                        decoration: const InputDecoration(labelText: 'Estado'),
                        items: EstadoAndroid.values
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _estado = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                EquipoFotosField(
                  fotos: _fotos,
                  carpeta: _carpetaFotos,
                  onChanged: (fotos) => setState(() => _fotos = fotos),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _costoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Costo', prefixText: 'USD \$ '),
                  validator: (v) => _validarDecimalPositivo(v, campo: 'El costo'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _precioVentaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio de venta (opcional)',
                    helperText: 'Se puede dejar en blanco y definirlo al vender',
                    prefixText: 'USD \$ ',
                  ),
                  validator: (v) => _validarDecimalOpcional(v, campo: 'El precio de venta'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _mesesGarantia,
                  decoration: const InputDecoration(labelText: 'Garantía'),
                  items: opcionesGarantia
                      .map((m) => DropdownMenuItem(value: m, child: Text(_labelMesesGarantia(m))))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _mesesGarantia = value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inversión compartida'),
                  subtitle: const Text('El equipo tiene un socio con % de ganancia'),
                  value: _esCompartido,
                  onChanged: (value) => setState(() => _esCompartido = value),
                ),
                if (_esCompartido) ...[
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _nombreSocioCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre del socio'),
                    validator: (v) =>
                        _esCompartido ? _validarRequerido(v, campo: 'El nombre del socio') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _porcentajeSocioCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '% del socio',
                      hintText: 'Ej: 50',
                      suffixText: '%',
                    ),
                    validator: _validarPorcentajeSocio,
                  ),
                ],
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
                        : Text(_esEdicion ? 'Guardar cambios' : 'Guardar equipo'),
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
