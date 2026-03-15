class Notificacion {
  final int id;
  final String numero;
  final String fecha;
  final String modificacion;
  final String fechaEmision;
  final String ubicacion;
  final String placa;
  final String cedula;
  final String nombres;
  final String? apellidos;
  final String telefono;
  final String direccion;
  final String email;
  final bool estado;
  final bool anulado;
  final String observacion;
  final String numeroComprobante;
  final bool eliminado;
  final bool impugnacion;
  final String? fechaResolucion;
  final bool impugnacionFavorable;
  final bool impugnacionNoFavorable;
  final String? observacionImpugnacion;
  final String? resolucion;
  final String? numeroResolucion;
  final int usuario;

  Notificacion({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.modificacion,
    required this.fechaEmision,
    required this.ubicacion,
    required this.placa,
    required this.cedula,
    required this.nombres,
    this.apellidos,
    required this.telefono,
    required this.direccion,
    required this.email,
    required this.estado,
    required this.anulado,
    required this.observacion,
    required this.numeroComprobante,
    required this.eliminado,
    required this.impugnacion,
    this.fechaResolucion,
    required this.impugnacionFavorable,
    required this.impugnacionNoFavorable,
    this.observacionImpugnacion,
    this.resolucion,
    this.numeroResolucion,
    required this.usuario,
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) {
    return Notificacion(
      id: json['id'] as int? ?? 0,
      numero: json['numero'] as String? ?? 'N/A',
      fecha: json['fecha'] as String? ?? 'N/A',
      modificacion: json['modificacion'] as String? ?? 'N/A',
      fechaEmision: json['fecha_emision'] as String? ?? 'N/A',
      ubicacion: json['ubicacion'] as String? ?? 'N/A',
      placa: json['placa'] as String? ?? 'N/A',
      cedula: json['cedula'] as String? ?? 'N/A',
      nombres: json['nombres'] as String? ?? 'N/A',
      apellidos: json['apellidos'] as String?,
      telefono: json['telefono'] as String? ?? 'N/A',
      direccion: json['direccion'] as String? ?? 'N/A',
      email: json['email'] as String? ?? 'N/A',
      estado: json['estado'] as bool? ?? false,
      anulado: json['anulado'] as bool? ?? false,
      observacion: json['observacion'] as String? ?? '',
      numeroComprobante: json['numero_comprobante'] as String? ?? 'N/A',
      eliminado: json['eliminado'] as bool? ?? false,
      impugnacion: json['impugnacion'] as bool? ?? false,
      fechaResolucion: json['fecha_resolucion'] as String?,
      impugnacionFavorable: json['impugnacion_favorable'] as bool? ?? false,
      impugnacionNoFavorable:
          json['impugnacion_no_favorable'] as bool? ?? false,
      observacionImpugnacion: json['observacion_impugnacion'] as String?,
      resolucion: json['resolucion'] as String?,
      numeroResolucion: json['numero_resolucion'] as String?,
      usuario: json['usuario'] as int? ?? 0,
    );
  }

  // Método para convertir string a DateTime si es necesario
  DateTime? get fechaEmisionDateTime {
    try {
      if (fechaEmision == 'N/A') return null;
      return DateTime.parse(fechaEmision);
    } catch (e) {
      return null;
    }
  }

  // Método para formatear la fecha de emisión
  String get fechaEmisionFormateada {
    if (fechaEmision == 'N/A') return 'Fecha no disponible';

    final date = fechaEmisionDateTime;
    if (date == null) {
      // Intentar formatear manualmente si el parsing falla
      try {
        if (fechaEmision.length >= 10) {
          final fechaPart = fechaEmision.substring(0, 10);
          final partes = fechaPart.split('-');
          if (partes.length == 3) {
            return '${partes[2]}/${partes[1]}/${partes[0]}';
          }
        }
        return fechaEmision;
      } catch (e) {
        return fechaEmision;
      }
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numero': numero,
      'fecha': fecha,
      'modificacion': modificacion,
      'fecha_emision': fechaEmision,
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
      'numero_comprobante': numeroComprobante,
      'eliminado': eliminado,
      'impugnacion': impugnacion,
      'fecha_resolucion': fechaResolucion,
      'impugnacion_favorable': impugnacionFavorable,
      'impugnacion_no_favorable': impugnacionNoFavorable,
      'observacion_impugnacion': observacionImpugnacion,
      'resolucion': resolucion,
      'numero_resolucion': numeroResolucion,
      'usuario': usuario,
    };
  }
}
