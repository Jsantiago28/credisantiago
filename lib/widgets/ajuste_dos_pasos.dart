import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/dos_pasos.dart';
import '../services/errores.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Perfil: activar o quitar la verificación en dos pasos (opcional).
class AjusteDosPasos extends StatefulWidget {
  const AjusteDosPasos({super.key});

  @override
  State<AjusteDosPasos> createState() => _AjusteDosPasosState();
}

class _AjusteDosPasosState extends State<AjusteDosPasos> {
  /// null mientras se pregunta (o si no se pudo saber).
  bool? _activa;

  @override
  void initState() {
    super.initState();
    _activa = DosPasos.factorActivo != null; // lo de la sesión, al momento
    _revisar();
  }

  Future<void> _revisar() async {
    try {
      final activa = await DosPasos.activada();
      if (mounted) setState(() => _activa = activa);
    } catch (_) {
      // Sin señal: se queda con lo que dice la sesión.
    }
  }

  Future<void> _activar() async {
    final listo = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const ActivarDosPasosScreen()));
    if (listo == true) {
      setState(() => _activa = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Listo: desde ahora, al entrar se te pedirá el código.')));
      }
    }
  }

  Future<void> _quitar() async {
    final si = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar la verificación en dos pasos?'),
        content: const Text('Tu cuenta queda protegida solo con la contraseña.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitarla'),
          ),
        ],
      ),
    );
    if (si != true || !mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await DosPasos.desactivar();
      if (mounted) setState(() => _activa = false);
      mensajero.showSnackBar(const SnackBar(content: Text('Verificación en dos pasos quitada.')));
    } catch (e, pila) {
      registrarError(e, pila, 'QUITAR DOS PASOS');
      mensajero.showSnackBar(
          SnackBar(content: Text('No se pudo quitar. ${mensajeError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activa = _activa == true;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, color: activa ? AppColors.green : AppColors.grey),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Verificación en dos pasos',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (activa) Pildora('Activada', color: AppColors.green),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            activa
                ? 'Al entrar se te pide la contraseña y el código de tu app de códigos.'
                : 'Opcional. Además de la contraseña, al entrar se pide un código de una app '
                    'del teléfono (Google Authenticator). Si alguien sabe tu contraseña, igual no entra.',
            style: TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (activa)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: _quitar,
              icon: const Icon(Icons.remove_moderator_rounded),
              label: const Text('Quitarla'),
            )
          else
            OutlinedButton.icon(
              onPressed: _activar,
              icon: const Icon(Icons.add_moderator_rounded),
              label: const Text('Activarla'),
            ),
        ],
      ),
    );
  }
}

/// Los pasos para activarla: instalar la app, agregar la cuenta (QR, botón
/// o clave) y escribir el primer código. Devuelve true si quedó activada.
class ActivarDosPasosScreen extends StatefulWidget {
  const ActivarDosPasosScreen({super.key});

  @override
  State<ActivarDosPasosScreen> createState() => _ActivarDosPasosScreenState();
}

class _ActivarDosPasosScreenState extends State<ActivarDosPasosScreen> {
  ({String factorId, String uri, String clave})? _datos;
  String? _errorCarga;
  final _codigo = TextEditingController();
  bool _revisando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _empezar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _empezar() async {
    setState(() => _errorCarga = null);
    try {
      final datos = await DosPasos.empezar();
      if (mounted) setState(() => _datos = datos);
    } catch (e, pila) {
      registrarError(e, pila, 'EMPEZAR DOS PASOS');
      if (mounted) setState(() => _errorCarga = mensajeError(e));
    }
  }

  Future<void> _confirmar() async {
    final datos = _datos;
    if (datos == null) return;
    if (!codigoBienEscrito(_codigo.text)) {
      setState(() => _error = 'Escribe los 6 números que salen en la app.');
      return;
    }
    setState(() {
      _revisando = true;
      _error = null;
    });
    try {
      await DosPasos.verificar(datos.factorId, _codigo.text.replaceAll(' ', ''));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _revisando = false;
          _error = mensajeCodigo(e);
        });
      }
    }
  }

  /// La clave en grupos de 4, para copiarla a mano sin perderse.
  String _enGrupos(String clave) => [
        for (var i = 0; i < clave.length; i += 4)
          clave.substring(i, i + 4 > clave.length ? clave.length : i + 4),
      ].join(' ');

  Widget _paso(int n, String texto) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text('$n. $texto', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación en dos pasos')),
      body: _errorCarga != null
          ? Vacio(icono: Icons.cloud_off, texto: 'No se pudo empezar.\n$_errorCarga')
          : datos == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _paso(1, 'Instala una app de códigos'),
                    Text(
                      'En el teléfono: Google Authenticator o Microsoft Authenticator '
                      '(gratis, en Play Store o App Store).',
                      style: TextStyle(color: AppColors.grey),
                    ),
                    _paso(2, 'Agrega CrediSantiago en esa app'),
                    if (android) ...[
                      ElevatedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(datos.uri),
                            mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Abrir en mi app de códigos'),
                      ),
                      const SizedBox(height: 8),
                      Text('O, desde otro teléfono, escanea este código:',
                          style: TextStyle(color: AppColors.grey)),
                    ] else
                      Text('En la app toca "+" y escanea este código con el teléfono:',
                          style: TextStyle(color: AppColors.grey)),
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(12),
                        child: QrImageView(data: datos.uri, size: 200),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('¿No puedes escanear? Escribe esta clave en la app:',
                        style: TextStyle(color: AppColors.grey)),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(_enGrupos(datos.clave),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          tooltip: 'Copiar la clave',
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: datos.clave));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Clave copiada.')));
                          },
                        ),
                      ],
                    ),
                    _paso(3, 'Escribe el código que te da la app'),
                    TextField(
                      controller: _codigo,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w800),
                      decoration:
                          InputDecoration(counterText: '', hintText: '000000', errorText: _error),
                      onSubmitted: (_) => _confirmar(),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _revisando ? null : _confirmar,
                      child: _revisando
                          ? const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Activar'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Guarda bien el teléfono con la app: si lo pierdes, escríbele al soporte de '
                      'CrediSantiago para que te quiten los dos pasos.',
                      style: TextStyle(color: AppColors.grey, fontSize: 12),
                    ),
                  ],
                ),
    );
  }
}
