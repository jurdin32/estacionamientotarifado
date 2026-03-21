class Estacionamiento {
  final int id;
  final int numero;
  final String direccion;
  final String placa;
  final bool estado;

  Estacionamiento({
    required this.id,
    required this.numero,
    required this.direccion,
    required this.placa,
    required this.estado,
  });

  factory Estacionamiento.fromJson(Map<String, dynamic> json) =>
      Estacionamiento(
        id: json['id'],
        numero: json['numero'],
        direccion: json['direccion'],
        placa: json['placa'] ?? '',
        estado: json['estado'],
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'numero': numero,
    'direccion': direccion,
    'placa': placa,
    'estado': estado,
  };
}
