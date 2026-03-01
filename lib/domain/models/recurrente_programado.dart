class RecurrenteProgramado {
  const RecurrenteProgramado({
    this.id,
    this.userId,
    required this.item,
    required this.monto,
    required this.categoria,
    required this.cuenta,
    required this.tipo,
    required this.frecuencia,
    required this.fechaProximoPago,
    this.activo = true,
  });

  final int? id;
  final String? userId;
  final String item;
  final int monto;
  final String categoria;
  final String cuenta;
  final String tipo;
  final String frecuencia;
  final DateTime fechaProximoPago;
  final bool activo;

  RecurrenteProgramado copyWith({
    int? id,
    String? userId,
    String? item,
    int? monto,
    String? categoria,
    String? cuenta,
    String? tipo,
    String? frecuencia,
    DateTime? fechaProximoPago,
    bool? activo,
  }) {
    return RecurrenteProgramado(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      item: item ?? this.item,
      monto: monto ?? this.monto,
      categoria: categoria ?? this.categoria,
      cuenta: cuenta ?? this.cuenta,
      tipo: tipo ?? this.tipo,
      frecuencia: frecuencia ?? this.frecuencia,
      fechaProximoPago: fechaProximoPago ?? this.fechaProximoPago,
      activo: activo ?? this.activo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'item': item,
      'monto': monto,
      'categoria': categoria,
      'cuenta': cuenta,
      'tipo': tipo,
      'frecuencia': frecuencia,
      'fecha_proximo_pago': fechaProximoPago.toIso8601String(),
      'activo': activo,
    };
  }

  factory RecurrenteProgramado.fromMap(Map<String, dynamic> map) {
    return RecurrenteProgramado(
      id: (map['id'] as num?)?.toInt(),
      userId: map['user_id']?.toString(),
      item: (map['item'] ?? '').toString(),
      monto: (map['monto'] as num? ?? 0).toInt(),
      categoria: (map['categoria'] ?? '').toString(),
      cuenta: (map['cuenta'] ?? '').toString(),
      tipo: (map['tipo'] ?? '').toString(),
      frecuencia: (map['frecuencia'] ?? 'Mensual').toString(),
      fechaProximoPago: DateTime.parse(
        (map['fecha_proximo_pago'] ?? '').toString(),
      ),
      activo: map['activo'] != false,
    );
  }
}
