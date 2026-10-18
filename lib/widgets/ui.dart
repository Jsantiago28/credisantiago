import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'foto_privada.dart';

/// Monto como se muestra en la app: RD$156,000 (con centavos solo si los
/// tiene, ej. cuotas viejas de 144.44).
String rd(num v) {
  final d = v.toDouble();
  final formato = NumberFormat(d == d.roundToDouble() ? '#,##0' : '#,##0.00', 'en_US');
  return 'RD\$${formato.format(d)}';
}

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// "23 sep 2026"
String fechaLarga(DateTime f) => '${f.day} ${_meses[f.month - 1]} ${f.year}';

/// "23 sep"
String fechaCorta(DateTime f) => '${f.day} ${_meses[f.month - 1]}';

/// Tarjeta base: superficie, borde tenue, esquinas redondeadas y, en el modo
/// claro, una sombra suave para que se vea "flotando" sobre el fondo.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borde;
  final VoidCallback? onTap;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.borde,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final forma = BorderRadius.circular(18);
    final claro = AppColors.paleta.brillo == Brightness.light;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: forma,
          // En el modo oscuro una sombra no se ve: solo en el claro.
          boxShadow: claro
              ? const [
                  BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 4)),
                ]
              : null,
        ),
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: forma,
            side: BorderSide(color: borde ?? AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// "¡Bienvenido, Juan!" justo después de iniciar sesión (una sola vez por
/// entrada; no al volver a abrir la app con la sesión ya abierta).
void darBienvenida(BuildContext context, String nombre) {
  final servicio = SupabaseService.instance;
  if (!servicio.bienvenidaPendiente) return;
  servicio.bienvenidaPendiente = false;
  final primero = nombre.trim().split(RegExp(r'\s+')).first;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Row(
        children: [
          const LogoApp(tamano: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(primero.isEmpty ? '¡Bienvenido a CrediSantiago!' : '¡Bienvenido, $primero!',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
    ));
  });
}

/// El logo de CrediSantiago (la "C" con la flecha), con las esquinas
/// redondeadas como un ícono de app.
class LogoApp extends StatelessWidget {
  final double tamano;
  const LogoApp({super.key, this.tamano = 44});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(tamano * 0.22),
      child: Image.asset('assets/branding/icono.png',
          width: tamano, height: tamano, fit: BoxFit.cover, semanticLabel: 'CrediSantiago'),
    );
  }
}

/// Círculo con las iniciales del cliente (o su foto, si tiene).
class AvatarIniciales extends StatelessWidget {
  final String nombre;
  final String? fotoUrl;
  final double tamano;

  const AvatarIniciales({super.key, required this.nombre, this.fotoUrl, this.tamano = 48});

  static const _fondos = [
    Color(0xFF1DB954),
    Color(0xFF3A4A45),
    Color(0xFF2E7D5B),
    Color(0xFF4B5563),
    Color(0xFF15803D),
  ];

  String get _iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fondo = _fondos[nombre.hashCode.abs() % _fondos.length];
    final iniciales = CircleAvatar(
      radius: tamano / 2,
      backgroundColor: fondo,
      child: Text(_iniciales,
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: tamano * 0.36)),
    );
    if (fotoUrl == null) return iniciales;
    // La foto está en el bucket privado: mientras carga (o si falla) se ven
    // las iniciales.
    return ClipOval(
      child: FotoPrivada(guardado: fotoUrl, width: tamano, height: tamano, sinFoto: iniciales),
    );
  }
}

/// Estado de cobro de un cliente, con sus colores.
enum EstadoCobro {
  alDia('AL DÍA', Icons.check_circle),
  venceHoy('VENCE HOY', Icons.schedule),
  atrasado('ATRASADO', Icons.warning_amber_rounded);

  final String texto;
  final IconData icono;
  const EstadoCobro(this.texto, this.icono);

  /// Los colores salen de la paleta elegida (clara u oscura).
  Color get color => switch (this) {
        alDia => AppColors.green,
        venceHoy => AppColors.amber,
        atrasado => AppColors.red,
      };

  Color get fondo => switch (this) {
        alDia => AppColors.greenDark,
        venceHoy => AppColors.amberDark,
        atrasado => AppColors.redDark,
      };
}

/// Etiqueta de estado tipo píldora (AL DÍA / VENCE HOY / ATRASADO).
class EtiquetaEstado extends StatelessWidget {
  final EstadoCobro estado;
  const EtiquetaEstado(this.estado, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: estado.fondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(estado.icono, size: 14, color: estado.color),
          const SizedBox(width: 4),
          Text(estado.texto,
              style: TextStyle(
                  color: estado.color, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Píldora pequeña de texto (ej. "HOY • 3").
class Pildora extends StatelessWidget {
  final String texto;

  /// Si no se da, verde (y su fondo suave).
  final Color? color;
  final Color? fondo;
  const Pildora(this.texto, {super.key, this.color, this.fondo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: fondo ?? AppColors.greenDark, borderRadius: BorderRadius.circular(20)),
      child: Text(texto,
          style: TextStyle(
              color: color ?? AppColors.green, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}

/// Tarjeta de total del tablero (EN LA CALLE, POR COBRAR HOY, ATRASADOS).
class TarjetaTotal extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;
  final String detalle;
  final Color color;
  final Color fondoIcono;
  final bool seleccionada;
  final VoidCallback? onTap;

  const TarjetaTotal({
    super.key,
    required this.icono,
    required this.titulo,
    required this.valor,
    required this.detalle,
    required this.color,
    required this.fondoIcono,
    this.seleccionada = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      borde: seleccionada ? color.withValues(alpha: 0.7) : null,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: fondoIcono,
              borderRadius: BorderRadius.circular(14),
              boxShadow: seleccionada
                  ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18)]
                  : null,
            ),
            child: Icon(icono, color: color, size: 28),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(titulo,
                style: TextStyle(color: AppColors.grey, fontSize: 11, letterSpacing: 0.3)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(valor,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(detalle,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Botones para elegir la frecuencia de cobro (diario / semanal /
/// quincenal / mensual).
class SelectorFrecuencia extends StatelessWidget {
  final String valor;
  final ValueChanged<String> onCambio;
  const SelectorFrecuencia({super.key, required this.valor, required this.onCambio});

  static const _opciones = {
    'diario': 'Diario',
    'semanal': 'Semanal',
    'quincenal': 'Quincenal',
    'mensual': 'Mensual',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final e in _opciones.entries) ...[
          Expanded(
            child: Material(
              color: e.key == valor ? AppColors.greenDark : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: e.key == valor ? AppColors.green : AppColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onCambio(e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(e.value,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: e.key == valor ? AppColors.green : AppColors.grey)),
                  ),
                ),
              ),
            ),
          ),
          if (e.key != 'mensual') const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Mensaje centrado para listas vacías.
class Vacio extends StatelessWidget {
  final IconData icono;
  final String texto;
  const Vacio({super.key, required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(icono, size: 40, color: AppColors.grey),
          const SizedBox(height: 12),
          Text(texto, textAlign: TextAlign.center, style: TextStyle(color: AppColors.grey)),
        ],
      ),
    );
  }
}
