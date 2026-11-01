import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/dominio.dart';
import '../services/errores.dart';
import '../services/supabase_service.dart';

/// Abre una de las páginas legales del sitio (/terminos, /privacidad,
/// /borrar-cuenta) en el navegador.
Future<void> abrirPaginaLegal(String pagina) =>
    launchUrl(Uri.parse('$kDominioBase/$pagina'), mode: LaunchMode.externalApplication);

/// "Borrar mi cuenta" (lo exige Google Play y la Ley 172-13). Pide escribir
/// BORRAR para que nadie lo haga por accidente. [queSeBorra] explica qué se
/// pierde (no es lo mismo para un prestamista que para un cobrador).
class BotonBorrarCuenta extends StatelessWidget {
  final String queSeBorra;
  const BotonBorrarCuenta({super.key, required this.queSeBorra});

  Future<void> _borrar(BuildContext context) async {
    final palabra = TextEditingController();
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstado) => AlertDialog(
          title: const Text('¿Borrar tu cuenta para siempre?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(queSeBorra),
                const SizedBox(height: 8),
                const Text('Esto no se puede deshacer. Si quieres guardar tu información, '
                    'descarga antes tus reportes en Excel.'),
                const SizedBox(height: 12),
                const Text('Para confirmar, escribe BORRAR:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextField(
                  controller: palabra,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setEstado(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            TextButton(
              onPressed: palabra.text.trim().toUpperCase() == 'BORRAR'
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Borrar mi cuenta'),
            ),
          ],
        ),
      ),
    );
    palabra.dispose();
    if (seguro != true || !context.mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.instance.borrarMiCuenta();
      mensajero.showSnackBar(const SnackBar(content: Text('Tu cuenta fue borrada.')));
    } catch (e, pila) {
      registrarError(e, pila, 'BORRAR CUENTA');
      mensajero.showSnackBar(SnackBar(
          content: Text('No se pudo borrar la cuenta. Escríbenos por WhatsApp para hacerlo. ($e)')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => _borrar(context),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('Borrar mi cuenta'),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(onPressed: () => abrirPaginaLegal('terminos'), child: const Text('Términos')),
            TextButton(onPressed: () => abrirPaginaLegal('privacidad'), child: const Text('Privacidad')),
          ],
        ),
      ],
    );
  }
}

/// Casilla "Acepto…" con enlaces a los Términos y a la Política de privacidad.
/// [texto] va antes de los enlaces. [color] para los enlaces (el formulario
/// público usa su azul).
class CasillaAcepto extends StatelessWidget {
  final bool valor;
  final ValueChanged<bool> onCambio;
  final String texto;
  final bool conTerminos;
  final Color? color;

  const CasillaAcepto({
    super.key,
    required this.valor,
    required this.onCambio,
    required this.texto,
    this.conTerminos = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final enlace = TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: valor, activeColor: color, onChanged: (v) => onCambio(v ?? false)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(onTap: () => onCambio(!valor), child: Text(texto)),
                if (conTerminos) ...[
                  TextButton(
                      style: enlace,
                      onPressed: () => abrirPaginaLegal('terminos'),
                      child: const Text('Términos de uso')),
                  const Text('y la'),
                ],
                TextButton(
                    style: enlace,
                    onPressed: () => abrirPaginaLegal('privacidad'),
                    child: const Text('Política de privacidad')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
