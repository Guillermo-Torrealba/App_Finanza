class Movimiento {
  const Movimiento({
    this.id,
    this.userId,
    required this.fecha,
    required this.item,
    this.detalle = '',
    required this.monto,
    required this.categoria,
    required this.cuenta,
    required this.tipo,
    this.metodoPago = 'Debito',
  });

  final int? id;
  final String? userId;
  final DateTime fecha;
  final String item;
  final String detalle;
  final int monto;
  final String categoria;
  final String cuenta;
  final String tipo;
  final String metodoPago;

  bool get esIngreso => tipo == 'Ingreso';
  bool get esGasto => tipo == 'Gasto';
  bool get esCredito => metodoPago == 'Credito';

  Movimiento copyWith({
    int? id,
    String? userId,
    DateTime? fecha,
    String? item,
    String? detalle,
    int? monto,
    String? categoria,
    String? cuenta,
    String? tipo,
    String? metodoPago,
  }) {
    return Movimiento(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fecha: fecha ?? this.fecha,
      item: item ?? this.item,
      detalle: detalle ?? this.detalle,
      monto: monto ?? this.monto,
      categoria: categoria ?? this.categoria,
      cuenta: cuenta ?? this.cuenta,
      tipo: tipo ?? this.tipo,
      metodoPago: metodoPago ?? this.metodoPago,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'fecha': fecha.toIso8601String(),
      'item': item,
      'detalle': detalle,
      'monto': monto,
      'categoria': categoria,
      'cuenta': cuenta,
      'tipo': tipo,
      'metodo_pago': metodoPago,
    };
  }

  factory Movimiento.fromMap(Map<String, dynamic> map) {
    return Movimiento(
      id: (map['id'] as num?)?.toInt(),
      userId: map['user_id']?.toString(),
      fecha: DateTime.parse((map['fecha'] ?? '').toString()),
      item: (map['item'] ?? '').toString(),
      detalle: (map['detalle'] ?? '').toString(),
      monto: (map['monto'] as num? ?? 0).toInt(),
      categoria: (map['categoria'] ?? '').toString(),
      cuenta: (map['cuenta'] ?? '').toString(),
      tipo: (map['tipo'] ?? '').toString(),
      metodoPago: (map['metodo_pago'] ?? 'Debito').toString(),
    );
  }
}
