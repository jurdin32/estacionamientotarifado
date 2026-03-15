class Estacionamiento_Tarjeta {
  final String fecha;
  final String horaEntrada;
  final String horaSalida;
  final int tiempo;
  final int t;
  final int estacionId;
  final String placa;
  final int usuario;

  Estacionamiento_Tarjeta({
    required this.fecha,
    required this.horaEntrada,
    required this.horaSalida,
    required this.tiempo,
    required this.estacionId,
    required this.t,
    required this.placa,
    required this.usuario,
  });

  factory Estacionamiento_Tarjeta.fromJson(Map<String, dynamic> json) =>
      Estacionamiento_Tarjeta(
        fecha: json['fecha'],
        horaEntrada: json['hora_entrada'],
        horaSalida: json['hora_salida'],
        tiempo: json['tiempo'],
        estacionId: json['estacion'],
        t: json['t'],
        placa: json['placa'],
        usuario: json['usuario'],
      );

  Map<String, dynamic> toJson() => {
    'fecha': fecha,
    'hora_entrada': horaEntrada,
    'hora_salida': horaSalida,
    'tiempo': tiempo,
    'estacion': estacionId,
    'placa': placa,
    't': t,
    'usuario': usuario,
  };
}
