/// Clientes archivados ("eliminados" de la lista): no se borran, se pueden
/// restaurar. Ver migracion_2026_10_18_archivar_clientes.sql.
library;

/// El cliente está archivado (fuera de la lista).
bool estaArchivado(Map<String, dynamic> cliente) => cliente['archivado_en'] != null;

/// Préstamo con dinero en la calle: mientras tenga uno, el cliente no se
/// puede eliminar de la lista.
bool prestamoActivo(String? estado) =>
    const {'en_calle', 'por_cobrar', 'atrasado'}.contains(estado);
