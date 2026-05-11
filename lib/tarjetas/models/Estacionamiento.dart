class Estacionamiento {
  final int id;
  final int numero;
  final String direccion;
  final String placa;
  final bool estado;

  /// Timestamp ISO 8601 de la última actualización en el servidor.
  /// Se usa para detectar conflictos de versión al hacer merge
  /// entre datos locales y remotos (WS / polling).
  /// Es opcional para mantener compatibilidad con caché existente.
  final String? updatedAt;

  Estacionamiento({
    required this.id,
    required this.numero,
    required this.direccion,
    required this.placa,
    required this.estado,
    this.updatedAt,
  });

  factory Estacionamiento.fromJson(Map<String, dynamic> json) =>
      Estacionamiento(
        id: json['id'],
        numero: json['numero'],
        direccion: json['direccion'],
        placa: json['placa'] ?? '',
        estado: json['estado'],
        updatedAt: json['updated_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'numero': numero,
    'direccion': direccion,
    'placa': placa,
    'estado': estado,
    if (updatedAt != null) 'updated_at': updatedAt,
  };

  /// Crea una copia con campos opcionalmente reemplazados.
  Estacionamiento copyWith({
    int? id,
    int? numero,
    String? direccion,
    String? placa,
    bool? estado,
    String? updatedAt,
  }) => Estacionamiento(
    id: id ?? this.id,
    numero: numero ?? this.numero,
    direccion: direccion ?? this.direccion,
    placa: placa ?? this.placa,
    estado: estado ?? this.estado,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
