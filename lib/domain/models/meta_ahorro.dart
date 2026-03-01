class MetaAhorro {
  const MetaAhorro({
    this.id,
    this.userId,
    required this.nombre,
    required this.montoMeta,
    required this.montoActual,
    this.completada = false,
    this.emoji,
    this.colorHex = '#009688',
    this.fechaLimite,
    this.updatedAt,
  });

  final int? id;
  final String? userId;
  final String nombre;
  final int montoMeta;
  final int montoActual;
  final bool completada;
  final String? emoji;
  final String colorHex;
  final DateTime? fechaLimite;
  final DateTime? updatedAt;

  double get progreso => montoMeta <= 0 ? 0 : (montoActual / montoMeta);

  MetaAhorro copyWith({
    int? id,
    String? userId,
    String? nombre,
    int? montoMeta,
    int? montoActual,
    bool? completada,
    String? emoji,
    String? colorHex,
    DateTime? fechaLimite,
    DateTime? updatedAt,
  }) {
    return MetaAhorro(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      nombre: nombre ?? this.nombre,
      montoMeta: montoMeta ?? this.montoMeta,
      montoActual: montoActual ?? this.montoActual,
      completada: completada ?? this.completada,
      emoji: emoji ?? this.emoji,
      colorHex: colorHex ?? this.colorHex,
      fechaLimite: fechaLimite ?? this.fechaLimite,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'nombre': nombre,
      'monto_meta': montoMeta,
      'monto_actual': montoActual,
      'completada': completada,
      'emoji': emoji,
      'color': colorHex,
      'fecha_limite': fechaLimite?.toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory MetaAhorro.fromMap(Map<String, dynamic> map) {
    return MetaAhorro(
      id: (map['id'] as num?)?.toInt(),
      userId: map['user_id']?.toString(),
      nombre: (map['nombre'] ?? '').toString(),
      montoMeta: (map['monto_meta'] as num? ?? 0).toInt(),
      montoActual: (map['monto_actual'] as num? ?? 0).toInt(),
      completada: map['completada'] == true,
      emoji: map['emoji']?.toString(),
      colorHex: (map['color'] ?? '#009688').toString(),
      fechaLimite: map['fecha_limite'] != null
          ? DateTime.tryParse(map['fecha_limite'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }
}
