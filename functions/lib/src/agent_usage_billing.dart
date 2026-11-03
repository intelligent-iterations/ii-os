part of 'agent_usage_event.dart';

final class AgentUsageBilling {
  const AgentUsageBilling({
    required this.mode,
    required this.provider,
    this.plan,
    this.subscriptionCostUsdMonthly,
  });

  const AgentUsageBilling.unknown()
    : mode = 'unknown',
      provider = 'unknown',
      plan = null,
      subscriptionCostUsdMonthly = null;

  factory AgentUsageBilling.parse(Map<String, Object?> json) {
    _expectKeys(json, const {
      'mode',
      'provider',
      'plan',
      'subscriptionCostUsdMonthly',
    });
    final mode = _identifier(json['mode'], 'billing.mode', 40);
    if (!const {
      'subscription_included',
      'metered_api',
      'metered_credits',
      'cloud_provider',
      'unknown',
    }.contains(mode)) {
      throw const ApiError(
        400,
        'invalid_agent_usage_event',
        'billing.mode is invalid.',
      );
    }
    final monthlyCost = _optionalMoney(
      json['subscriptionCostUsdMonthly'],
      'subscriptionCostUsdMonthly',
    );
    if (monthlyCost != null && mode != 'subscription_included') {
      throw const ApiError(
        400,
        'invalid_agent_usage_event',
        'A subscription cost requires subscription-included billing.',
      );
    }
    return AgentUsageBilling(
      mode: mode,
      provider: _identifier(json['provider'], 'billing.provider', 64),
      plan: _optionalIdentifier(json['plan'], 'billing.plan', 128),
      subscriptionCostUsdMonthly: monthlyCost,
    );
  }

  final String mode;
  final String provider;
  final String? plan;
  final double? subscriptionCostUsdMonthly;
}
