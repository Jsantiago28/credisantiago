import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_datos;
import 'package:timezone/timezone.dart' as tz;

/// Recordatorio diario en el teléfono ("Revisa los cobros de hoy"). Lo hace
/// el mismo teléfono, sin internet ni servidores: solo en la app de Android
/// (en la web no hay).
class Recordatorio {
  static const _claveActivo = 'recordatorio_activo';
  static const _claveHora = 'recordatorio_hora'; // minutos desde medianoche
  static const _id = 1;
  static const horaInicial = TimeOfDay(hour: 8, minute: 0);

  static final _avisos = FlutterLocalNotificationsPlugin();
  static bool _listo = false;

  /// Solo en la app de Android.
  static bool get disponible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<({bool activo, TimeOfDay hora})> ajustes() async {
    final prefs = await SharedPreferences.getInstance();
    final minutos = prefs.getInt(_claveHora);
    return (
      activo: prefs.getBool(_claveActivo) ?? true,
      hora: minutos == null ? horaInicial : TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60),
    );
  }

  /// Al entrar a la app: deja programado el recordatorio con lo que eligió
  /// el usuario (encendido a las 8:00 a. m. si nunca lo cambió).
  static Future<void> alEntrar() async {
    if (!disponible) return;
    try {
      final a = await ajustes();
      if (a.activo) {
        await _programar(a.hora);
      } else {
        await _iniciar();
        await _avisos.cancel(id: _id);
      }
    } catch (e) {
      // ignore: avoid_print
      print('ERROR REAL RECORDATORIO: $e');
    }
  }

  /// Cambia el recordatorio desde Perfil.
  static Future<void> guardar({required bool activo, required TimeOfDay hora}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveActivo, activo);
    await prefs.setInt(_claveHora, hora.hour * 60 + hora.minute);
    await alEntrar();
  }

  static Future<void> _iniciar() async {
    if (_listo) return;
    tz_datos.initializeTimeZones();
    // República Dominicana: todo el año a la misma hora (sin horario de verano).
    tz.setLocalLocation(tz.getLocation('America/Santo_Domingo'));
    await _avisos.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _listo = true;
  }

  static Future<void> _programar(TimeOfDay hora) async {
    await _iniciar();
    // Android 13 o más nuevo pide permiso para mostrar avisos.
    await _avisos
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _avisos.zonedSchedule(
      id: _id,
      title: 'Cobros de hoy',
      body: 'Abre CrediSantiago y revisa a quién te toca cobrar hoy.',
      scheduledDate: proximaVez(tz.TZDateTime.now(tz.local), hora),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'recordatorio_diario',
          'Recordatorio diario',
          channelDescription: 'Un aviso cada día para revisar los cobros.',
        ),
      ),
      // Sin hora exacta: Android puede atrasarlo unos minutos, pero no pide
      // permisos especiales.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// La próxima vez que toca el aviso: hoy a [hora] si todavía no pasó, si
  /// no, mañana.
  @visibleForTesting
  static tz.TZDateTime proximaVez(tz.TZDateTime ahora, TimeOfDay hora) {
    var cuando =
        tz.TZDateTime(ahora.location, ahora.year, ahora.month, ahora.day, hora.hour, hora.minute);
    if (!cuando.isAfter(ahora)) cuando = cuando.add(const Duration(days: 1));
    return cuando;
  }
}
