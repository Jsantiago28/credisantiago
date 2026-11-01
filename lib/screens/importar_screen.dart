import 'package:flutter/material.dart';

import '../archivos/archivos.dart';
import '../logic/importar.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Clientes → Importar desde Excel: bajar la plantilla, elegir el archivo,
/// ver qué filas están bien y cuáles no, e importar las buenas.
class ImportarScreen extends StatefulWidget {
  final String prestamistaId;

  /// Para pruebas: un archivo ya revisado.
  final List<FilaImportada>? filas;

  const ImportarScreen({super.key, required this.prestamistaId, this.filas});

  @override
  State<ImportarScreen> createState() => _ImportarScreenState();
}

class _ImportarScreenState extends State<ImportarScreen> {
  late List<FilaImportada>? _filas = widget.filas;
  String? _archivo;
  String? _error;
  bool _leyendo = false;

  /// Mientras importa: cuántas van.
  int? _hechas;

  /// Al terminar: los que se importaron y los que no (con el motivo).
  int? _importados;
  final _fallidos = <(FilaImportada, String)>[];

  List<FilaImportada> get _listas => (_filas ?? const []).where((f) => f.lista).toList();

  void _plantilla() {
    try {
      descargarArchivo('plantilla_clientes.xlsx', plantillaExcel());
    } catch (e) {
      setState(() => _error = mensajeError(e));
    }
  }

  Future<void> _elegir() async {
    setState(() {
      _error = null;
      _importados = null;
      _fallidos.clear();
    });
    try {
      final archivo = await elegirArchivo(tipos: '.xlsx,.csv');
      if (archivo == null) return;
      setState(() => _leyendo = true);
      final celdas = leerCeldas(archivo.bytes, archivo.nombre);
      final existentes = await SupabaseService.instance.cedulasDeMisClientes(widget.prestamistaId);
      final r = revisarArchivo(celdas, cedulasExistentes: existentes, hoy: DateTime.now());
      if (!mounted) return;
      setState(() {
        _leyendo = false;
        _archivo = archivo.nombre;
        if (r.faltan.isNotEmpty) {
          _filas = null;
          _error = 'Al archivo le faltan columnas: ${r.faltan.join(', ')}. '
              'Usa la plantilla (la primera fila son los títulos).';
        } else {
          _filas = r.filas;
          if (r.filas.isEmpty) _error = 'El archivo no tiene clientes debajo de los títulos.';
        }
      });
    } catch (e, pila) {
      registrarError(e, pila, 'LEER EXCEL');
      if (mounted) {
        setState(() {
          _leyendo = false;
          _error = 'No se pudo leer el archivo. Guárdalo como Excel (.xlsx) o CSV y prueba otra vez.';
        });
      }
    }
  }

  Future<void> _importar() async {
    final listas = _listas;
    setState(() => _hechas = 0);
    var importados = 0;
    for (final f in listas) {
      try {
        await SupabaseService.instance.importarCliente(widget.prestamistaId, f);
        importados++;
      } on LimitePlan catch (e) {
        // Se acabó el cupo del plan: los que faltan tampoco van a entrar.
        for (final resto in listas.skip(importados + _fallidos.length)) {
          _fallidos.add((resto, e.mensaje));
        }
        break;
      } catch (e, pila) {
        registrarError(e, pila, 'IMPORTAR FILA ${f.fila}');
        _fallidos.add((f, mensajeError(e)));
      }
      if (mounted) setState(() => _hechas = importados + _fallidos.length);
    }
    if (mounted) {
      setState(() {
        _hechas = null;
        _importados = importados;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar desde Excel')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_importados != null)
            _resultado()
          else ...[
            _pasos(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: AppColors.red)),
              ),
            if (_leyendo) const Center(child: CircularProgressIndicator()),
            if (filas != null && filas.isNotEmpty) ...[
              if (_archivo != null)
                Text(_archivo!, style: TextStyle(color: AppColors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              ResumenImportacion(filas: filas),
              const SizedBox(height: 12),
              if (_hechas != null) ...[
                LinearProgressIndicator(value: _hechas! / _listas.length),
                const SizedBox(height: 6),
                Text('Importando ${_hechas! + 1 > _listas.length ? _listas.length : _hechas! + 1} '
                    'de ${_listas.length}…'),
              ] else
                ElevatedButton.icon(
                  onPressed: _listas.isEmpty ? null : _importar,
                  icon: const Icon(Icons.upload_rounded),
                  label: Text('Importar ${_listas.length} cliente(s)'),
                ),
              const SizedBox(height: 16),
              ...filas.map((f) => FilaRevisada(fila: f)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _pasos() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('1. Baja la plantilla y llénala con tus clientes.',
              style: TextStyle(fontWeight: FontWeight.w700)),
          Text(
            'Nombre, cédula y teléfono son obligatorios. Si el cliente tiene un préstamo en la '
            'calle, llena también monto, interés, frecuencia, plazo, fecha y lo que ya pagó. '
            '"Tipo de interés": fijo (sobre el monto, como se presta en la calle) o saldo '
            '(sobre lo que debe, cuota fija); si lo dejas vacío, es fijo. '
            'Lo que ya pagó cuenta desde hoy: las cuotas atrasadas de antes empiezan a '
            'cobrar mora desde hoy, no desde que vencieron. '
            'Borra las filas de ejemplo.',
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          TextButton.icon(
            onPressed: _plantilla,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Descargar plantilla'),
          ),
          const SizedBox(height: 4),
          const Text('2. Elige el archivo (Excel o CSV).',
              style: TextStyle(fontWeight: FontWeight.w700)),
          Text('Antes de guardar nada, te mostramos qué filas están bien.',
              style: TextStyle(color: AppColors.grey, fontSize: 12)),
          TextButton.icon(
            onPressed: _leyendo || _hechas != null ? null : _elegir,
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(_filas == null ? 'Elegir archivo' : 'Elegir otro archivo'),
          ),
        ],
      ),
    );
  }

  Widget _resultado() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          borde: AppColors.green.withValues(alpha: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle, color: AppColors.green, size: 36),
              const SizedBox(height: 8),
              Text('Listo: $_importados cliente(s) importado(s)',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(
                'Lo que ya habían pagado cuenta para su balance, pero no como dinero de la caja.',
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        if (_fallidos.isNotEmpty) ...[
          Text('${_fallidos.length} no se pudieron importar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.red)),
          for (final (f, motivo) in _fallidos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Fila ${f.fila}: ${f.nombre}'),
              subtitle: Text(motivo, style: TextStyle(color: AppColors.grey, fontSize: 12)),
            ),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Ver mis clientes'),
        ),
      ],
    );
  }
}

/// Cuántas filas están listas, cuántas ya existen y cuántas tienen errores.
class ResumenImportacion extends StatelessWidget {
  final List<FilaImportada> filas;
  const ResumenImportacion({super.key, required this.filas});

  @override
  Widget build(BuildContext context) {
    final listas = filas.where((f) => f.lista).length;
    final conPrestamo = filas.where((f) => f.lista && f.prestamo != null).length;
    final repetidas = filas.where((f) => f.repetido && f.errores.isEmpty).length;
    final conErrores = filas.where((f) => f.errores.isNotEmpty).length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Pildora('$listas listo(s)'),
        if (conPrestamo > 0) Pildora('$conPrestamo con préstamo'),
        if (repetidas > 0)
          Pildora('$repetidas ya existe(n)', color: AppColors.amber, fondo: AppColors.amberDark),
        if (conErrores > 0)
          Pildora('$conErrores con errores', color: AppColors.red, fondo: AppColors.redDark),
      ],
    );
  }
}

/// Una fila del archivo: lista (con su préstamo), repetida o con errores.
class FilaRevisada extends StatelessWidget {
  final FilaImportada fila;
  const FilaRevisada({super.key, required this.fila});

  @override
  Widget build(BuildContext context) {
    final f = fila;
    final (icono, color) = f.errores.isNotEmpty
        ? (Icons.error_outline, AppColors.red)
        : f.repetido
            ? (Icons.content_copy_rounded, AppColors.amber)
            : (Icons.check_circle_outline, AppColors.green);
    final p = f.prestamo;
    final detalle = f.errores.isNotEmpty
        ? f.errores.join(' · ')
        : f.repetido
            ? 'Ya tienes un cliente con esa cédula: no se importa'
            : p == null
                ? 'Sin préstamo en la calle'
                : _detallePrestamo(p);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icono, color: color),
      title: Text('Fila ${f.fila}: ${f.nombre.isEmpty ? '(sin nombre)' : f.nombre}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(detalle,
          style: TextStyle(color: f.errores.isNotEmpty ? AppColors.red : AppColors.grey, fontSize: 12)),
    );
  }

  static String _detallePrestamo(PrestamoImportado p) {
    final debe = p.montoTotal - p.yaPago;
    return 'Préstamo ${rd(p.monto)} ${p.frecuencia}, interés ${p.tipo.valor}, '
        'del ${fechaLarga(p.fecha)} · '
        '${debe <= 0 ? 'ya saldado' : 'debe ${rd(debe)}'}';
  }
}
