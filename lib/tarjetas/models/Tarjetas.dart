class Estacionamiento_Tarjeta {
  final String fecha;
  final String horaEntrada;
  final String horaSalida;
  final int tiempo;
  final int t;
  final int estacionId;
  final String placa;
  final int usuario;
  final String usuarioNombre; // Nombre extraído del objeto usuario anidado

  Estacionamiento_Tarjeta({
    required this.fecha,
    required this.horaEntrada,
    required this.horaSalida,
    required this.tiempo,
    required this.estacionId,
    required this.t,
    required this.placa,
    required this.usuario,
    this.usuarioNombre = '',
  });

  factory Estacionamiento_Tarjeta.fromJson(Map<String, dynamic> json) {
    int usuarioId;
    String usuarioNombre = '';

    // 1. Intentar obtener usuarioNombre directamente del JSON (guardado en caché)
    final nombreGuardado = json['usuario_nombre'] as String? ?? '';
    if (nombreGuardado.isNotEmpty) {
      usuarioNombre = nombreGuardado;
    }

    final usuarioRaw = json['usuario'];
    if (usuarioRaw is Map<String, dynamic>) {
      // El servidor envía un objeto anidado con datos del usuario
      usuarioId = (usuarioRaw['id'] as int?) ?? 0;
      // Solo extraer nombre si no vino ya guardado en caché
      if (usuarioNombre.isEmpty) {
        final first = (usuarioRaw['first_name'] as String? ?? '').trim();
        final last = (usuarioRaw['last_name'] as String? ?? '').trim();
        final full = '$first $last'.trim();
        usuarioNombre = full.isNotEmpty
            ? full
            : (usuarioRaw['name'] as String? ?? '').trim();
      }
    } else if (usuarioRaw is int) {
      usuarioId = usuarioRaw;
    } else if (usuarioRaw is Map) {
      // Caso borde: Map pero no Map<String, dynamic>
      usuarioId = (usuarioRaw['id'] as int?) ?? 0;
      if (usuarioNombre.isEmpty) {
        final first = (usuarioRaw['first_name'] as String? ?? '').trim();
        final last = (usuarioRaw['last_name'] as String? ?? '').trim();
        final full = '$first $last'.trim();
        usuarioNombre = full.isNotEmpty
            ? full
            : (usuarioRaw['name'] as String? ?? '').trim();
      }
    } else {
      usuarioId = int.tryParse((usuarioRaw ?? '').toString()) ?? 0;
    }

    return Estacionamiento_Tarjeta(
      fecha: json['fecha'] ?? '',
      horaEntrada: json['hora_entrada'] ?? '',
      horaSalida: json['hora_salida'] ?? '',
      tiempo: json['tiempo'] ?? 0,
      estacionId: json['estacion'] ?? 0,
      t: json['t'] ?? 0,
      placa: json['placa'] ?? '',
      usuario: usuarioId,
      usuarioNombre: usuarioNombre,
    );
  }

  Map<String, dynamic> toJson() => {
    'fecha': fecha,
    'hora_entrada': horaEntrada,
    'hora_salida': horaSalida,
    'tiempo': tiempo,
    'estacion': estacionId,
    'placa': placa,
    't': t,
    'usuario': usuario,
    'usuario_nombre': usuarioNombre,
  };
}
