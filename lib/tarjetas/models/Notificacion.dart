class DetalleNotificacion {
  final Notificacion notificacion;
  final DateTime fecha;
  final double total; // NO nullable - la API lo acepta como número
  final bool estado; // La API acepta true/false
  final bool procede; // La API acepta true/false
  final int multa; // NO nullable - la API lo acepta como número

  DetalleNotificacion({
    required this.notificacion,
    required this.fecha,
    required this.total,
    required this.estado,
    required this.procede,
    required this.multa,
  });

  factory DetalleNotificacion.fromJson(Map<String, dynamic> json) {
    return DetalleNotificacion(
      notificacion: Notificacion.fromJson(json['notificacion']),
      fecha: DateTime.parse(json['fecha']),
      total: double.tryParse(json['total'].toString()) ?? 0.0,
      estado: json['estado'],
      procede: json['procede'],
      multa: json['multa'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notificacion': notificacion.toJson(),
      'fecha': fecha.toIso8601String(),
      'total': total, // Número, no string
      'estado': estado, // boolean
      'procede': procede, // boolean
      'multa': multa, // Número
    };
  }
}

class Notificacion {
  final int id;
  final String numero;
  final String fecha_emision; // NO nullable - la API acepta string con fecha
  final String ubicacion;
  final String placa;
  final String cedula;
  final String nombres;
  final String apellidos;
  final String telefono;
  final String direccion;
  final String email;
  final bool estado;
  final bool anulado;
  final String observacion;
  final String numero_comprobante;
  final bool eliminado;
  final bool impugnacion;
  final String? fecha_resolucion; // Mantener nullable
  final bool impugnacion_favorable;
  final bool impugnacion_no_favorable;
  final String observacion_impugnacion;
  final String? resolucion; // Mantener nullable
  final String numero_resolucion;
  final int usuario; // NO nullable - la API acepta número

  Notificacion({
    required this.id,
    required this.numero,
    required this.fecha_emision, // Requerido
    required this.ubicacion,
    required this.placa,
    required this.cedula,
    required this.nombres,
    required this.apellidos,
    required this.telefono,
    required this.direccion,
    required this.email,
    required this.estado,
    required this.anulado,
    required this.observacion,
    required this.numero_comprobante,
    required this.eliminado,
    required this.impugnacion,
    this.fecha_resolucion,
    required this.impugnacion_favorable,
    required this.impugnacion_no_favorable,
    required this.observacion_impugnacion,
    this.resolucion,
    required this.numero_resolucion,
    required this.usuario, // Requerido
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) {
    return Notificacion(
      id: json['id'],
      numero: json['numero']?.toString() ?? "",
      fecha_emision: json['fecha_emision']?.toString() ?? "",
      ubicacion: json['ubicacion'],
      placa: json['placa'],
      cedula: json['cedula'],
      nombres: json['nombres'],
      apellidos: json['apellidos'],
      telefono: json['telefono'],
      direccion: json['direccion'],
      email: json['email'],
      estado: json['estado'],
      anulado: json['anulado'],
      observacion: json['observacion'],
      numero_comprobante: json['numero_comprobante']?.toString() ?? "",
      eliminado: json['eliminado'],
      impugnacion: json['impugnacion'],
      fecha_resolucion: json['fecha_resolucion'],
      impugnacion_favorable: json['impugnacion_favorable'],
      impugnacion_no_favorable: json['impugnacion_no_favorable'],
      observacion_impugnacion: json['observacion_impugnacion'],
      resolucion: json['resolucion'],
      numero_resolucion: json['numero_resolucion'],
      usuario: json['usuario'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numero': numero,
      'fecha_emision': fecha_emision, // String con formato ISO
      'ubicacion': ubicacion,
      'placa': placa,
      'cedula': cedula,
      'nombres': nombres,
      'apellidos': apellidos,
      'telefono': telefono,
      'direccion': direccion,
      'email': email,
      'estado': estado,
      'anulado': anulado,
      'observacion': observacion,
      'numero_comprobante': numero_comprobante,
      'eliminado': eliminado,
      'impugnacion': impugnacion,
      'fecha_resolucion': fecha_resolucion,
      'impugnacion_favorable': impugnacion_favorable,
      'impugnacion_no_favorable': impugnacion_no_favorable,
      'observacion_impugnacion': observacion_impugnacion,
      'resolucion': resolucion,
      'numero_resolucion': numero_resolucion,
      'usuario': usuario,
    };
  }
}
