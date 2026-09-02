import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// IMPORTANTE: generá este archivo con `flutterfire configure` antes de compilar.
import 'firebase_options.dart';

import 'config/app_config.dart';

import 'models/android_model.dart';
import 'models/cliente_model.dart';
import 'models/deuda_model.dart';
import 'models/gasto_model.dart';
import 'models/ingreso_extra_model.dart';
import 'models/iphone_model.dart';
import 'models/pago_model.dart';
import 'models/stock_empresa_model.dart';
import 'models/venta_accesorio_model.dart';
import 'screens/android_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/finanzas_screen.dart';
import 'screens/gastos_screen.dart';
import 'screens/ingresos_extra_screen.dart';
import 'screens/iphones_screen.dart';
import 'screens/reportes_screen.dart';
import 'screens/stock_empresa_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AppRoot());
}

/// -----------------------------------------------------------------------
/// PROVIDERS
/// -----------------------------------------------------------------------

/// Maneja el estado de autenticación del usuario.
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get usuarioActual => _auth.currentUser;
  bool get estaAutenticado => _auth.currentUser != null;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<String?> iniciarSesion(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Error al iniciar sesión';
    }
  }

  Future<void> cerrarSesion() async {
    await _auth.signOut();
  }
}

/// Controla qué sección del Drawer está activa.
class NavigationProvider extends ChangeNotifier {
  int _indiceSeleccionado = 0;
  int get indiceSeleccionado => _indiceSeleccionado;

  void seleccionar(int index) {
    _indiceSeleccionado = index;
    notifyListeners();
  }
}

/// Expone el stock de iPhones (colección `iphones`) desde Firestore.
class IPhoneStockProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('iphones');

  Stream<List<IPhoneModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => IPhoneModel.fromSnapshot(d)).toList(),
      );

  Future<void> agregar(IPhoneModel iphone) => _col.add(iphone.toMap());

  Future<void> actualizar(IPhoneModel iphone) =>
      _col.doc(iphone.id).update(iphone.toMap());

  Future<void> eliminar(String id) => _col.doc(id).delete();
}

/// Expone el stock de equipos Android (colección `androids`).
class AndroidProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('androids');

  Stream<List<AndroidModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => AndroidModel.fromSnapshot(d)).toList(),
      );

  Future<void> agregar(AndroidModel equipo) => _col.add(equipo.toMap());

  Future<void> actualizar(AndroidModel equipo) =>
      _col.doc(equipo.id).update(equipo.toMap());

  Future<void> eliminar(String id) => _col.doc(id).delete();
}

/// Expone el stock de insumos/accesorios (colección `stock_empresa`).
class StockEmpresaProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('stock_empresa');

  Stream<List<StockEmpresaModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => StockEmpresaModel.fromSnapshot(d)).toList(),
      );

  Future<void> agregar(StockEmpresaModel item) => _col.add(item.toMap());

  Future<void> actualizar(StockEmpresaModel item) =>
      _col.doc(item.id).update(item.toMap());

  Future<void> eliminar(String id) => _col.doc(id).delete();
}

/// Expone las ventas registradas de Stock de Empresa (colección
/// `ventas_accesorios`). A diferencia de solo ajustar la cantidad en stock
/// (`StockEmpresaProvider.actualizar`), esto es lo que le permite a
/// reportes_screen.dart sumar cuánto se vendió de accesorios en cada
/// período -ver el comentario en `VentaAccesorioModel`-.
class VentaAccesorioProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('ventas_accesorios');

  Stream<List<VentaAccesorioModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => VentaAccesorioModel.fromSnapshot(d)).toList(),
      );

  Future<void> agregar(VentaAccesorioModel venta) => _col.add(venta.toMap());

  Future<void> eliminar(String id) => _col.doc(id).delete();
}

/// Expone los clientes (colección `clientes`), usados por deudores y
/// acreedores. Los IDs pueden venir de la importación masiva desde Excel
/// (`ID_Cliente`) o ser autogenerados por Firestore al crear un cliente
/// nuevo desde la app.
class ClienteProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('clientes');

  Stream<List<ClienteModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => ClienteModel.fromSnapshot(d)).toList(),
      );

  /// Crea un cliente nuevo y devuelve el ID de documento generado.
  Future<String> agregar(ClienteModel cliente) async {
    final ref = await _col.add(cliente.toMap());
    return ref.id;
  }

  Future<void> actualizar(ClienteModel cliente) =>
      _col.doc(cliente.id).update(cliente.toMap());

  Future<void> eliminar(String id) => _col.doc(id).delete();
}

/// Expone los pagos (colección de nivel superior `pagos`), vinculados a su
/// cuenta mediante el campo `idDeuda`. Las escrituras que también deben
/// actualizar el saldo de la deuda viven en [DeudaProvider] para que ambas
/// operaciones ocurran en un mismo batch.
class PagoProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('pagos');

  Stream<List<PagoModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => PagoModel.fromSnapshot(d)).toList(),
      );

  /// Trae los pagos de una cuenta una sola vez (no como stream). Se usa,
  /// por ejemplo, para armar el resumen que se manda por WhatsApp sin
  /// depender de que el historial de la tarjeta esté expandido/suscripto.
  Future<List<PagoModel>> obtenerPorDeuda(String idDeuda) async {
    final snap = await _col.where('idDeuda', isEqualTo: idDeuda).get();
    return snap.docs.map((d) => PagoModel.fromSnapshot(d)).toList();
  }

  /// Historial de pagos de una cuenta puntual, en vivo.
  ///
  /// A propósito NO tiene ningún `.timeout()` acá: un listener de
  /// Firestore sano puede quedarse en silencio indefinidamente si no hay
  /// pagos nuevos (eso es el estado normal, no un error). Un `.timeout()`
  /// sobre el stream completo se reinicia con cada evento, así que después
  /// de unos segundos sin cambios lo confunde con una conexión trabada y
  /// dispara un error falso -eso fue justamente lo que pasó al agregarlo
  /// acá antes-. El resguardo contra un primer evento que nunca llega vive
  /// en `_HistorialPagos` (finanzas_screen.dart), como un timeout de una
  /// sola vez que se cancela apenas llega cualquier evento.
  Stream<List<PagoModel>> porDeuda(String idDeuda) => _col
      .where('idDeuda', isEqualTo: idDeuda)
      .snapshots()
      .map((snap) => snap.docs.map((d) => PagoModel.fromSnapshot(d)).toList());
}

/// Expone deudores/acreedores (colección `deudas`).
///
/// Esquema alineado con la importación masiva desde Excel: `idCliente`,
/// `concepto`, `montoTotal`, `fechaEmision`, `estado`. Los pagos viven en la
/// colección de nivel superior `pagos` (campo `idDeuda`), no en una
/// subcolección.
class DeudaProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('deudas');
  final _pagosCol = FirebaseFirestore.instance.collection('pagos');

  Stream<List<DeudaModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => DeudaModel.fromSnapshot(d)).toList(),
      );

  Future<void> agregar(DeudaModel deuda) => _col.add(deuda.toMap());

  Future<void> actualizar(DeudaModel deuda) =>
      _col.doc(deuda.id).update(deuda.toMap());

  Future<void> eliminar(String id) => _col.doc(id).delete();

  /// Recalcula el campo `estado` (valores binarios en minúscula) a partir
  /// del saldo pendiente resultante.
  String _estadoSegun(double montoAbonado, double montoTotal) =>
      montoAbonado >= montoTotal ? 'pagado' : 'pendiente';

  /// Registra un abono parcial: fija el nuevo `montoAbonado` (y `estado`) de
  /// la deuda y guarda el movimiento en `pagos`, todo en un mismo batch para
  /// que ambas escrituras se apliquen juntas.
  Future<void> registrarPago(
    DeudaModel deuda,
    double monto, {
    String nota = '',
    required String medioPago,
    // Cotización del dólar blue al momento de cobrar, solo para cuentas de
    // venta financiada (ver DeudaModel.esVentaFinanciada). La usa
    // reportes_screen.dart para convertir este pago a USD con el valor del
    // blue de ESE día, no el de hoy.
    double? tasaBlue,
  }) async {
    final nuevoMontoAbonado = deuda.montoAbonado + monto;
    final deudaRef = _col.doc(deuda.id);
    final pagoRef = _pagosCol.doc();

    final batch = FirebaseFirestore.instance.batch();
    batch.update(deudaRef, {
      'montoAbonado': nuevoMontoAbonado,
      'estado': _estadoSegun(nuevoMontoAbonado, deuda.montoTotal),
    });
    batch.set(pagoRef, {
      'idDeuda': deuda.id,
      'montoAbonado': monto,
      'fechaPago': Timestamp.now(),
      'nota': nota,
      'tasaBlue': tasaBlue,
      'metodoPago': medioPago,
    });
    await batch.commit();
  }

  /// Corrige el monto (y opcionalmente la nota / medio de pago) de un abono
  /// ya registrado. Ajusta `montoAbonado`/`estado` de la deuda por la
  /// diferencia, en el mismo batch, para que el saldo pendiente quede
  /// siempre consistente con el historial.
  Future<void> editarPago(
    DeudaModel deuda,
    String pagoId, {
    required double montoAnterior,
    required double montoNuevo,
    String? nota,
    String? medioPago,
  }) async {
    final nuevoMontoAbonado = deuda.montoAbonado - montoAnterior + montoNuevo;
    final deudaRef = _col.doc(deuda.id);
    final pagoRef = _pagosCol.doc(pagoId);

    final batch = FirebaseFirestore.instance.batch();
    batch.update(deudaRef, {
      'montoAbonado': nuevoMontoAbonado,
      'estado': _estadoSegun(nuevoMontoAbonado, deuda.montoTotal),
    });
    final cambiosPago = <String, dynamic>{'montoAbonado': montoNuevo};
    if (nota != null) cambiosPago['nota'] = nota;
    if (medioPago != null) cambiosPago['metodoPago'] = medioPago;
    batch.update(pagoRef, cambiosPago);
    await batch.commit();
  }

  /// Elimina un abono del historial (por error de carga) y revierte su
  /// efecto sobre `montoAbonado`/`estado` en el mismo batch.
  Future<void> eliminarPago(DeudaModel deuda, String pagoId, double monto) async {
    final nuevoMontoAbonado = deuda.montoAbonado - monto;
    final deudaRef = _col.doc(deuda.id);
    final pagoRef = _pagosCol.doc(pagoId);

    final batch = FirebaseFirestore.instance.batch();
    batch.update(deudaRef, {
      'montoAbonado': nuevoMontoAbonado,
      'estado': _estadoSegun(nuevoMontoAbonado, deuda.montoTotal),
    });
    batch.delete(pagoRef);
    await batch.commit();
  }

  /// Marca una cuenta como pagada de una sola vez: salda el resto del
  /// saldo pendiente (si queda algo) registrando un pago por esa
  /// diferencia —para que quede en el historial de abonos igual que un
  /// pago normal—, fija `estado` en 'pagado' y guarda `fechaPago` con el
  /// momento actual.
  Future<void> marcarComoPagado(DeudaModel deuda, {String medioPago = 'efectivo'}) async {
    final saldo = deuda.saldoPendiente;
    final ahora = Timestamp.now();
    final deudaRef = _col.doc(deuda.id);

    final batch = FirebaseFirestore.instance.batch();
    batch.update(deudaRef, {
      'montoAbonado': deuda.montoTotal,
      'estado': 'pagado',
      'fechaPago': ahora,
    });
    if (saldo > 0) {
      final pagoRef = _pagosCol.doc();
      batch.set(pagoRef, {
        'idDeuda': deuda.id,
        'montoAbonado': saldo,
        'fechaPago': ahora,
        'nota': 'Saldo cerrado al marcar la cuenta como pagada',
        'metodoPago': medioPago,
      });
    }
    await batch.commit();
  }

  /// Revierte una cuenta marcada como pagada por error: la vuelve a dejar
  /// en 'pendiente' y borra `fechaPago`. No modifica `montoAbonado` ni el
  /// historial de pagos ya registrado (si hace falta corregir el monto
  /// abonado, se hace desde el historial de pagos).
  Future<void> reabrirCuenta(String deudaId) {
    return _col.doc(deudaId).update({
      'estado': 'pendiente',
      'fechaPago': null,
    });
  }
}

/// Expone los egresos del negocio (colección `gastos`).
class GastoProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('gastos');

  Stream<List<GastoModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => GastoModel.fromSnapshot(d)).toList(),
      );

  Future<void> agregar(GastoModel gasto) => _col.add(gasto.toMap());

  Future<void> actualizar(GastoModel gasto) =>
      _col.doc(gasto.id).update(gasto.toMap());

  Future<void> eliminar(String id) => _col.doc(id).delete();
}

/// Expone los ingresos del negocio que no vienen de la venta de un equipo
/// (reparaciones, arreglos, otros servicios) — colección `ingresos_extra`.
class IngresoExtraProvider extends ChangeNotifier {
  final _col = FirebaseFirestore.instance.collection('ingresos_extra');

  Stream<List<IngresoExtraModel>> get stream => _col.snapshots().map(
        (snap) => snap.docs.map((d) => IngresoExtraModel.fromSnapshot(d)).toList(),
      );

  Future<void> agregar(IngresoExtraModel ingreso) => _col.add(ingreso.toMap());

  Future<void> actualizar(IngresoExtraModel ingreso) =>
      _col.doc(ingreso.id).update(ingreso.toMap());

  Future<void> eliminar(String id) => _col.doc(id).delete();
}

/// -----------------------------------------------------------------------
/// APP ROOT
/// -----------------------------------------------------------------------

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => IPhoneStockProvider()),
        ChangeNotifierProvider(create: (_) => AndroidProvider()),
        ChangeNotifierProvider(create: (_) => StockEmpresaProvider()),
        ChangeNotifierProvider(create: (_) => VentaAccesorioProvider()),
        ChangeNotifierProvider(create: (_) => ClienteProvider()),
        ChangeNotifierProvider(create: (_) => PagoProvider()),
        ChangeNotifierProvider(create: (_) => DeudaProvider()),
        ChangeNotifierProvider(create: (_) => GastoProvider()),
        ChangeNotifierProvider(create: (_) => IngresoExtraProvider()),
      ],
      child: MaterialApp(
        title: AppConfig.nombreApp,
        debugShowCheckedModeBanner: false,
        theme: _appTheme,
        home: const AuthGate(),
      ),
    );
  }
}

/// Tema visual moderno de la app: fondo suave (no blanco plano), tarjetas
/// con esquinas redondeadas y sombra sutil, y campos de texto rellenados con
/// etiquetas claras en todos los formularios/diálogos/modales.
final ThemeData _appTheme = ThemeData(
  // Tono principal azul-violeta oscuro, estilo iOS (systemIndigo), para que
  // tarjetas, botones e indicadores resalten de forma consistente en toda
  // la app.
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5856D6)),
  textTheme: GoogleFonts.interTextTheme(),
  useMaterial3: true,

  // Fondo suave en vez de blanco plano, para que las tarjetas con degradado
  // resalten en todas las pantallas.
  scaffoldBackgroundColor: const Color(0xFFF4F6F8),

  // Tarjetas con esquinas redondeadas, borde sutil y sombra pequeña.
  cardTheme: CardThemeData(
    elevation: 0,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
    ),
  ),

  // Diálogos ("Agregar"/"Editar", confirmaciones) con esquinas redondeadas.
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),

  // Modales (showModalBottomSheet) con esquinas superiores redondeadas,
  // consistentes con el resto de la interfaz.
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
  ),

  // Campos de texto con fondo claro relleno y etiquetas legibles en todos
  // los formularios de "Agregar"/"Editar" de la app.
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    // Un tono apenas más oscuro que el fondo de pantalla, para que los
    // campos se distingan tanto sobre tarjetas/diálogos blancos como sobre
    // el fondo suave general.
    fillColor: const Color(0xFFEDF0F3),
    labelStyle: TextStyle(color: Colors.grey.shade700),
    hintStyle: TextStyle(color: Colors.grey.shade500),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF5856D6), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  ),
);

/// Decide si mostrar la pantalla de login o la app principal.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return StreamBuilder<User?>(
      stream: authProvider.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const HomeShell();
        }
        return const LoginScreen();
      },
    );
  }
}

/// -----------------------------------------------------------------------
/// LOGIN
/// -----------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _error;
  bool _cargando = false;

  Future<void> _login() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final authProvider = context.read<AuthProvider>();
    final error = await authProvider.iniciarSesion(
      _emailCtrl.text.trim(),
      _passCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Iniciar sesión', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _cargando ? null : _login,
                    child: _cargando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ingresar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// SHELL PRINCIPAL CON DRAWER
/// -----------------------------------------------------------------------

/// Cada pantalla del menú (Dashboard, Stock de iPhones, Stock de Empresa,
/// Deudas) es un Scaffold independiente con su propio AppBar y Drawer,
/// para que pantallas como [IPhonesScreen] puedan definir su propia barra
/// superior (buscador, filtros, FAB) sin quedar anidadas dentro de otro
/// Scaffold.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _paginas = [
    DashboardScreen(),
    IPhonesScreen(),
    AndroidScreen(),
    StockEmpresaScreen(),
    FinanzasScreen(),
    GastosScreen(),
    IngresosExtraScreen(),
    ReportesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final navProvider = context.watch<NavigationProvider>();
    final index = navProvider.indiceSeleccionado;
    return _paginas[index];
  }
}

/// Ítems del menú lateral: ícono, etiqueta y color de acento propio para
/// que cada sección sea reconocible de un vistazo.
const List<({IconData icon, String label, Color color})> _drawerItems = [
  (icon: Icons.dashboard_rounded, label: 'Dashboard', color: Color(0xFF5856D6)),
  (icon: Icons.phone_iphone_rounded, label: 'Stock de iPhones', color: Color(0xFF0A84FF)), // Azul iOS
  (icon: Icons.smartphone_rounded, label: 'Stock de Android', color: Color(0xFF12B886)), // Verde menta/esmeralda
  (icon: Icons.inventory_2_rounded, label: 'Stock de Empresa', color: Color(0xFFFF9500)),
  (icon: Icons.request_quote_rounded, label: 'Finanzas', color: Color(0xFF2F5AA8)), // Violeta/azul de banco
  (icon: Icons.receipt_long_rounded, label: 'Gastos', color: Color(0xFFD2691E)), // Naranja terracota
  (icon: Icons.handyman_rounded, label: 'Otros Ingresos', color: Color(0xFF34C759)), // Verde
  (icon: Icons.bar_chart_rounded, label: 'Balance & Reportes', color: Color(0xFF32ADE6)),
];

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final navProvider = context.read<NavigationProvider>();
    final authProvider = context.read<AuthProvider>();
    final indiceActual = context.watch<NavigationProvider>().indiceSeleccionado;
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      elevation: 8,
      shadowColor: colorScheme.primary.withValues(alpha: 0.3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _DrawerHeader(email: authProvider.usuarioActual?.email ?? ''),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _drawerItems.length,
                itemBuilder: (context, index) {
                  final item = _drawerItems[index];
                  return _DrawerMenuItem(
                    icon: item.icon,
                    label: item.label,
                    color: item.color,
                    seleccionado: indiceActual == index,
                    onTap: () {                      
                      Navigator.of(context).pop();
                      navProvider.seleccionar(index);
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            _DrawerMenuItem(
              icon: Icons.logout_rounded,
              label: 'Cerrar sesión',
              color: colorScheme.error,
              seleccionado: false,
              onTap: () => authProvider.cerrarSesion(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Encabezado del Drawer con degradado y esquinas suavizadas.
class _DrawerHeader extends StatelessWidget {
  final String email;
  const _DrawerHeader({required this.email});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.tertiary],
        ),
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: const Icon(Icons.phone_iphone_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            AppConfig.nombreApp,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Ítem del menú con ícono redondeado sobre fondo de color sutil.
class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool seleccionado;
  final VoidCallback onTap;

  const _DrawerMenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: seleccionado ? color.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: seleccionado ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w500,
                      color: seleccionado ? color : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

