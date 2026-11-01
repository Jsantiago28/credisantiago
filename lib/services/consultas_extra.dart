import 'supabase_service.dart';

/// Consultas pequeñas que usan algunas pantallas y que no están en
/// [SupabaseService] (para no tocar ese archivo grande).

/// Estado de todos los préstamos del prestamista (solo `cliente_id` y
/// `estado`): para saber quién pagó todo y ya no tiene préstamo.
Future<List<Map<String, dynamic>>> estadosDePrestamos(String prestamistaId) async {
  final filas = await SupabaseService.instance.client
      .from('prestamos')
      .select('cliente_id, estado')
      .eq('prestamista_id', prestamistaId);
  return [for (final f in filas) Map<String, dynamic>.from(f)];
}
