class Multa {
  final int id;
  final String tipo;
  final String detalleMulta;
  final double valor;
  final bool estado;

  Multa({
    required this.id,
    required this.tipo,
    required this.detalleMulta,
    required this.valor,
    required this.estado,
  });

  // Crear objeto desde JSON
  factory Multa.fromJson(Map<String, dynamic> json) {
    // Convertir 'valor' a double incluso si viene como String
    double valorParsed = 0.0;
    if (json['valor'] is String) {
      valorParsed = double.tryParse(json['valor']) ?? 0.0;
    } else if (json['valor'] is num) {
      valorParsed = (json['valor'] as num).toDouble();
    }

    return Multa(
      id: json['id'] ?? 0,
      tipo: json['tipo'] ?? '',
      detalleMulta: json['detalle_multa'] ?? '',
      valor: valorParsed,
      estado: json['estado'] ?? false,
    );
  }

  // Convertir objeto a JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tipo': tipo,
      'detalle_multa': detalleMulta,
      'valor': valor.toStringAsFixed(2), // opcional: mantener formato string
      'estado': estado,
    };
  }
}
