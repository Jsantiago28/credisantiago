import 'package:flutter/material.dart';
import '../logic/busqueda.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'calculadora_screen.dart';
import 'cliente_detalle_screen.dart';
import 'importar_screen.dart';
import 'nuevo_cliente_screen.dart';
import 'prestar_screen.dart';

class ClientesScreen extends StatefulWidget {
  final String prestamistaId;
  const ClientesScreen({super.key, required this.prestamistaId});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  // Consulta normal, no "tiempo real": si la conexión en vivo falla, la
  // pantalla no se queda cargando. Se recarga al entrar a la pestaña, al
  // volver de crear o ver un cliente, y jalando hacia abajo.
  List<Map<String, dynamic>>? _todos;
  String? _error;
  final _buscar = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final lista = await SupabaseService.instance.listarClientes(widget.prestamistaId);
      if (mounted) {
        setState(() {
          _todos = lista;
          _error = null;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL CLIENTES: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _abrir(Widget pantalla) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
    _cargar(); // pudo crear un cliente o prestarle a uno
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Importar desde Excel',
            icon: Icon(Icons.upload_file_rounded, color: AppColors.green),
            onPressed: () => _abrir(ImportarScreen(prestamistaId: widget.prestamistaId)),
          ),
          IconButton(
            tooltip: 'Calculadora de préstamos',
            icon: Icon(Icons.calculate_rounded, color: AppColors.green),
            onPressed: () => _abrir(CalculadoraScreen(prestamistaId: widget.prestamistaId)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.green,
        foregroundColor: AppColors.sobreVerde,
        onPressed: () => _abrir(NuevoClienteScreen(prestamistaId: widget.prestamistaId)),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo cliente', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    final todos = _todos;
    if (todos == null) {
      if (_error == null) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Vacio(icono: Icons.cloud_off, texto: 'No pudimos cargar tus clientes.\n$_error'),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _error = null);
                  _cargar();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final busqueda = _buscar.text.trim();
    final clientes =
        busqueda.isEmpty ? todos : buscarClientes(todos, busqueda, maximo: todos.length);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        // Espacio abajo para que el botón "Nuevo cliente" no tape la última tarjeta.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: clientes.length + 1,
        // key único por cliente: evita que la tarjeta se reinicie sola al
        // recargar la lista.
        itemBuilder: (_, i) {
          if (i > 0) {
            return _ClienteCard(
              key: ValueKey(clientes[i - 1]['id']),
              cliente: clientes[i - 1],
              onVolver: _cargar,
            );
          }
          if (todos.isEmpty) {
            return const Vacio(
              icono: Icons.people_outline,
              texto: 'Todavía no tienes clientes.\n'
                  'Aprueba una solicitud o toca "Nuevo cliente".',
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _buscar,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, cédula o teléfono',
                    prefixIcon: Icon(Icons.search, color: AppColors.grey),
                    suffixIcon: busqueda.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close, color: AppColors.grey),
                            onPressed: () => setState(_buscar.clear),
                          ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                    busqueda.isEmpty
                        ? '${todos.length} cliente(s)'
                        : '${clientes.length} de ${todos.length} cliente(s)',
                    style: TextStyle(color: AppColors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Tarjeta individual de cliente. Es su propio StatefulWidget para que la
/// consulta del préstamo se haga UNA sola vez (en initState) y no se
/// reinicie cada vez que la lista de clientes se recarga.
class _ClienteCard extends StatefulWidget {
  final Map<String, dynamic> cliente;

  /// Al volver de la ficha: la lista recarga (pudo cambiar el cliente).
  final VoidCallback? onVolver;
  const _ClienteCard({super.key, required this.cliente, this.onVolver});

  @override
  State<_ClienteCard> createState() => _ClienteCardState();
}

class _ClienteCardState extends State<_ClienteCard> {
  Map<String, dynamic>? _prestamo;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarPrestamo();
  }

  Future<void> _cargarPrestamo() async {
    try {
      final p = await SupabaseService.instance.obtenerUltimoPrestamo(widget.cliente['id']);
      if (mounted) {
        setState(() {
          _prestamo = p;
          _cargando = false;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL CLIENTE CARD: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  Future<void> _irAPrestar() async {
    if (_prestamo == null) return;
    final actualizado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PrestarScreen(cliente: widget.cliente, prestamo: _prestamo!),
      ),
    );
    if (actualizado == true) {
      _cargarPrestamo(); // refresca el estado (pasa de borrador a en_calle)
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;

    Widget accion;
    if (_cargando) {
      accion = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_error != null) {
      accion = Icon(Icons.error, color: AppColors.red);
    } else if (_prestamo?['estado'] == 'borrador') {
      accion = SizedBox(
        width: 110,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _irAPrestar,
          child: const Text('Prestar'),
        ),
      );
    } else if (_prestamo?['estado'] == 'en_calle') {
      accion = const Pildora('EN LA CALLE');
    } else if (_prestamo?['estado'] == 'pagado') {
      accion = Pildora('SALDADO', color: AppColors.grey, fondo: AppColors.surfaceAlt);
    } else {
      accion = Text('Sin préstamo',
          style: TextStyle(color: AppColors.grey, fontSize: 12));
    }

    final telefono = (c['telefono'] as String?) ?? '';
    final direccion = (c['direccion'] as String?) ?? '';

    return Panel(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ClienteDetalleScreen(clienteId: c['id'] as String),
        ));
        _cargarPrestamo(); // pudo prestarle o cobrarle desde la ficha
        widget.onVolver?.call();
      },
      child: Row(
        children: [
          AvatarIniciales(
              nombre: c['nombre'] ?? '', fotoUrl: c['foto_cara_url'] as String?),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c['nombre'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text([if (direccion.isNotEmpty) direccion, if (telefono.isNotEmpty) telefono]
                        .join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          accion,
        ],
      ),
    );
  }
}
