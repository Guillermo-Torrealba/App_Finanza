class CreditoConsumo {
  const CreditoConsumo({
    required this.id,
    required this.name,
    required this.amount,
    required this.installments,
    required this.paymentDay,
    required this.startDate,
    required this.cuenta,
    this.paidInstallments = 0,
  });

  final String id;
  final String name;
  final int amount;
  final int installments;
  final int paymentDay;
  final DateTime startDate;
  final String cuenta;
  final int paidInstallments;

  bool get isCompleted => paidInstallments >= installments;

  CreditoConsumo copyWith({
    String? id,
    String? name,
    int? amount,
    int? installments,
    int? paymentDay,
    DateTime? startDate,
    String? cuenta,
    int? paidInstallments,
  }) {
    return CreditoConsumo(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      installments: installments ?? this.installments,
      paymentDay: paymentDay ?? this.paymentDay,
      startDate: startDate ?? this.startDate,
      cuenta: cuenta ?? this.cuenta,
      paidInstallments: paidInstallments ?? this.paidInstallments,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'installments': installments,
      'paymentDay': paymentDay,
      'startDate': startDate.toIso8601String(),
      'cuenta': cuenta,
      'paidInstallments': paidInstallments,
    };
  }

  factory CreditoConsumo.fromMap(Map<String, dynamic> map) {
    return CreditoConsumo(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      amount: (map['amount'] as num? ?? 0).toInt(),
      installments: (map['installments'] as num? ?? 0).toInt(),
      paymentDay: (map['paymentDay'] as num? ?? 1).toInt(),
      startDate: DateTime.parse((map['startDate'] ?? '').toString()),
      cuenta: (map['cuenta'] ?? '').toString(),
      paidInstallments: (map['paidInstallments'] as num? ?? 0).toInt(),
    );
  }
}
