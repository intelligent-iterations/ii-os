part of 'agent_usage.dart';

enum AgentBillingMode {
  subscriptionIncluded('subscription_included', 'Subscription included'),
  meteredApi('metered_api', 'Metered API'),
  meteredCredits('metered_credits', 'Metered credits'),
  cloudProvider('cloud_provider', 'Cloud provider'),
  unknown('unknown', 'Unknown');

  const AgentBillingMode(this.value, this.label);

  final String value;
  final String label;

  static AgentBillingMode parse(String? value) => values.firstWhere(
    (mode) => mode.value == value,
    orElse: () => AgentBillingMode.unknown,
  );
}

final class AgentUsageAllocation {
  const AgentUsageAllocation({
    required this.jobName,
    required this.model,
    required this.billingMode,
    required this.billingProvider,
    required this.billingPlan,
    required this.totals,
  });

  factory AgentUsageAllocation.fromJson(JsonMap json) => AgentUsageAllocation(
    jobName: json['jobName']?.toString() ?? 'unknown',
    model: json['model']?.toString() ?? 'unknown',
    billingMode: AgentBillingMode.parse(json['billingMode']?.toString()),
    billingProvider: json['billingProvider']?.toString() ?? 'unknown',
    billingPlan: json['billingPlan']?.toString() ?? 'unknown',
    totals: AgentUsageTotals.fromJson(json),
  );

  final String jobName;
  final String model;
  final AgentBillingMode billingMode;
  final String billingProvider;
  final String billingPlan;
  final AgentUsageTotals totals;
}

final class AgentUsageSubscription {
  const AgentUsageSubscription({
    required this.billingProvider,
    required this.billingPlan,
    required this.monthlyCostUsd,
    required this.totals,
  });

  factory AgentUsageSubscription.fromJson(JsonMap json) =>
      AgentUsageSubscription(
        billingProvider: json['billingProvider']?.toString() ?? 'unknown',
        billingPlan: json['billingPlan']?.toString() ?? 'unknown',
        monthlyCostUsd: _nullableDecimal(json['monthlyCostUsd']),
        totals: AgentUsageTotals.fromJson(json),
      );

  final String billingProvider;
  final String billingPlan;
  final double? monthlyCostUsd;
  final AgentUsageTotals totals;
}
