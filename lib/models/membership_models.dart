import '../models/auth_models.dart';

class VipPackage {
  const VipPackage({
    required this.id,
    required this.name,
    required this.days,
    required this.priceYuan,
    required this.flameBonus,
    this.remark = '',
    this.labelDays = '',
  });

  final int id;
  final String name;
  final int days;
  final String priceYuan;
  final int flameBonus;
  final String remark;
  final String labelDays;

  factory VipPackage.fromJson(Map<String, dynamic> json) {
    return VipPackage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: '${json['name'] ?? ''}',
      days: (json['days'] as num?)?.toInt() ?? 0,
      priceYuan: '${json['price_yuan'] ?? '0'}',
      flameBonus: (json['flame_bonus'] as num?)?.toInt() ?? 0,
      remark: '${json['remark'] ?? ''}',
      labelDays: '${json['label_days'] ?? ''}',
    );
  }
}

class FlamePackage {
  const FlamePackage({
    required this.id,
    required this.name,
    required this.flameAmount,
    required this.priceYuan,
    this.remark = '',
  });

  final int id;
  final String name;
  final int flameAmount;
  final String priceYuan;
  final String remark;

  factory FlamePackage.fromJson(Map<String, dynamic> json) {
    return FlamePackage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: '${json['name'] ?? ''}',
      flameAmount: (json['flame_amount'] as num?)?.toInt() ?? 0,
      priceYuan: '${json['price_yuan'] ?? '0'}',
      remark: '${json['remark'] ?? ''}',
    );
  }
}

class MembershipOrder {
  const MembershipOrder({
    required this.id,
    required this.orderNo,
    required this.type,
    required this.packageName,
    required this.amountYuan,
    required this.status,
    required this.statusLabel,
    this.vipDays = 0,
    this.flameAmount = 0,
  });

  final int id;
  final String orderNo;
  final String type;
  final String packageName;
  final String amountYuan;
  final int status;
  final String statusLabel;
  final int vipDays;
  final int flameAmount;

  factory MembershipOrder.fromJson(Map<String, dynamic> json) {
    return MembershipOrder(
      id: (json['id'] as num?)?.toInt() ?? 0,
      orderNo: '${json['order_no'] ?? ''}',
      type: '${json['type'] ?? ''}',
      packageName: '${json['package_name'] ?? ''}',
      amountYuan: '${json['amount_yuan'] ?? '0'}',
      status: (json['status'] as num?)?.toInt() ?? 0,
      statusLabel: '${json['status_label'] ?? ''}',
      vipDays: (json['vip_days'] as num?)?.toInt() ?? 0,
      flameAmount: (json['flame_amount'] as num?)?.toInt() ?? 0,
    );
  }
}

class VipCatalogResult {
  const VipCatalogResult({
    required this.list,
    this.mockPay = true,
    this.freeMaxAccounts = 3,
    this.vipMaxAccounts = 20,
    this.flameCostSparkRenew = 1,
    this.me,
  });

  final List<VipPackage> list;
  final bool mockPay;
  final int freeMaxAccounts;
  final int vipMaxAccounts;
  final int flameCostSparkRenew;
  final AuthUser? me;
}

class FlameCatalogResult {
  const FlameCatalogResult({
    required this.list,
    this.mockPay = true,
    this.flameCostSparkRenew = 1,
    this.me,
  });

  final List<FlamePackage> list;
  final bool mockPay;
  final int flameCostSparkRenew;
  final AuthUser? me;
}

class OrderCreateResult {
  const OrderCreateResult({
    required this.order,
    this.user,
    this.message = '',
  });

  final MembershipOrder order;
  final AuthUser? user;
  final String message;
}
