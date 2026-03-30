import 'dart:convert';

/// Session
/// Mirrors the response from Uphold's Create Session endpoint.
///
/// See: https://developer.uphold.com/rest-apis/widgets-api/payment/create-session
class PaymentWidgetSession {
  final String url;
  final String token;
  final PaymentWidgetFlow flow;
  final Map<String, dynamic>? data;

  const PaymentWidgetSession({required this.url, required this.token, required this.flow, this.data});

  factory PaymentWidgetSession.fromJson(Map<String, dynamic> json) => switch (json) {
    {'url': String url, 'token': String token, 'flow': String flow} => PaymentWidgetSession(
      url: url,
      token: token,
      flow: PaymentWidgetFlow.fromString(flow),
      data: switch (json['data']) {
        Map<String, dynamic> data => data,
        _ => null,
      },
    ),
    _ => throw FormatException('Invalid PaymentWidgetSession JSON: $json'),
  };

  Map<String, dynamic> toJson() => {'url': url, 'token': token, 'flow': flow.value, 'data': ?data};
}

/// Flows
/// The three flows supported by the Payment Widget.
enum PaymentWidgetFlow {
  selectForDeposit('select-for-deposit'),
  selectForWithdrawal('select-for-withdrawal'),
  authorize('authorize');

  const PaymentWidgetFlow(this.value);

  final String value;

  static PaymentWidgetFlow fromString(String value) => PaymentWidgetFlow.values.firstWhere(
    (f) => f.value == value,
    orElse: () => throw ArgumentError('Unknown PaymentWidgetFlow: $value'),
  );
}

/// Payment method options (controls what the widget displays)
sealed class PaymentMethodOption {
  const PaymentMethodOption();
  Map<String, dynamic> toJson();
}

class CardPaymentMethod extends PaymentMethodOption {
  const CardPaymentMethod();

  @override
  Map<String, dynamic> toJson() => {'type': 'card'};
}

class BankPaymentMethod extends PaymentMethodOption {
  final PaymentAssetFilter? assets;

  const BankPaymentMethod({this.assets});

  @override
  Map<String, dynamic> toJson() => {'type': 'bank', 'assets': ?assets?.toJson()};
}

class CryptoPaymentMethod extends PaymentMethodOption {
  final PaymentAssetFilter? assets;

  const CryptoPaymentMethod({this.assets});

  @override
  Map<String, dynamic> toJson() => {'type': 'crypto', 'assets': ?assets?.toJson()};
}

/// Filter for the assets shown under bank / crypto payment methods.
///
/// Use **either** [include] or [exclude], not both.
class PaymentAssetFilter {
  final List<String>? include;
  final List<String>? exclude;

  const PaymentAssetFilter({this.include, this.exclude})
    : assert((include == null) || (exclude == null), 'Use either include or exclude, not both.');

  const PaymentAssetFilter.include(List<String> assets) : include = assets, exclude = null;

  const PaymentAssetFilter.exclude(List<String> assets) : include = null, exclude = assets;

  Map<String, dynamic> toJson() => {'include': ?include, 'exclude': ?exclude};
}

/// Widget options
class PaymentWidgetOptions {
  final bool debug;
  final List<PaymentMethodOption>? paymentMethods;

  const PaymentWidgetOptions({this.debug = false, this.paymentMethods});

  Map<String, dynamic> toJson() => {'debug': debug, 'paymentMethods': ?paymentMethods?.map((m) => m.toJson()).toList()};
}

/// Events
/// Umbrella type for all events dispatched by the Payment Widget.
sealed class PaymentWidgetEvent {
  const PaymentWidgetEvent();

  /// Deserialises a raw JSON string from the JavaScript bridge.
  factory PaymentWidgetEvent.fromMessage(String message) => switch (jsonDecode(message)) {
    {'type': 'ready'} => const PaymentWidgetReadyEvent(),
    {'type': 'complete', 'data': Map<String, dynamic> data} => PaymentWidgetCompleteEvent._fromJson(data),
    {'type': 'complete'} => PaymentWidgetCompleteEvent._fromJson({}),
    {'type': 'cancel'} => const PaymentWidgetCancelEvent(),
    {'type': 'error', 'data': Map<String, dynamic> data} => PaymentWidgetErrorEvent._fromJson(data),
    {'type': 'error'} => PaymentWidgetErrorEvent._fromJson({}),
    {'type': String type} => throw ArgumentError('Unknown PaymentWidgetEvent type: $type'),
    _ => throw const FormatException('Invalid PaymentWidgetEvent message'),
  };
}

class PaymentWidgetReadyEvent extends PaymentWidgetEvent {
  const PaymentWidgetReadyEvent();
}

class PaymentWidgetCancelEvent extends PaymentWidgetEvent {
  const PaymentWidgetCancelEvent();
}

/// Complete event + result types
class PaymentWidgetCompleteEvent extends PaymentWidgetEvent {
  final PaymentWidgetResult result;

  const PaymentWidgetCompleteEvent(this.result);

  factory PaymentWidgetCompleteEvent._fromJson(Map<String, dynamic> json) =>
      PaymentWidgetCompleteEvent(PaymentWidgetResult.fromJson(json));
}

/// Discriminated union of the possible completion results.
sealed class PaymentWidgetResult {
  const PaymentWidgetResult();

  factory PaymentWidgetResult.fromJson(Map<String, dynamic> json) => switch (json) {
    // The `authorize` flow returns { transaction, trigger } with no `via` key.
    {'transaction': Map<String, dynamic> transaction, 'trigger': {'reason': String reason}} => AuthorizeResult(
      transaction: transaction,
      triggerReason: reason,
    ),
    {'via': 'external-account', 'selection': Map<String, dynamic> selection} => ExternalAccountResult(
      selection: selection,
    ),
    {
      'via': 'deposit-method',
      'selection': {'depositMethod': Map<String, dynamic> depositMethod, 'account': Map<String, dynamic> account},
    } =>
      DepositMethodResult(depositMethod: depositMethod, account: account),
    {
      'via': 'crypto-network',
      'selection': {'network': String network, 'address': String address, 'reference': String? reference},
    } =>
      CryptoNetworkResult(network: network, address: address, reference: reference),
    _ => UnknownResult(raw: json),
  };
}

/// User selected a saved card or bank account.
class ExternalAccountResult extends PaymentWidgetResult {
  final Map<String, dynamic> selection;
  const ExternalAccountResult({required this.selection});
}

/// User chose a deposit method (bank transfer or crypto) — select-for-deposit flow.
class DepositMethodResult extends PaymentWidgetResult {
  /// Details about the deposit method (type, details, etc.).
  final Map<String, dynamic> depositMethod;

  /// The Uphold account the funds will land in.
  final Map<String, dynamic> account;

  const DepositMethodResult({required this.depositMethod, required this.account});
}

/// User provided a crypto address — select-for-withdrawal flow.
class CryptoNetworkResult extends PaymentWidgetResult {
  /// e.g. `'bitcoin'`, `'ethereum'`, `'xrp-ledger'`.
  final String network;

  final String address;

  /// Destination tag (XRP), memo (XLM), etc.
  final String? reference;

  const CryptoNetworkResult({required this.network, required this.address, this.reference});
}

/// Fallback for any `via` value the SDK adds in the future.
class UnknownResult extends PaymentWidgetResult {
  final Map<String, dynamic> raw;
  const UnknownResult({required this.raw});
}

/// Authorize result (for the `authorize` flow)
/// Result from the `authorize` flow (e.g. 3DS card authentication).
class AuthorizeResult extends PaymentWidgetResult {
  final Map<String, dynamic> transaction;
  final String triggerReason;

  const AuthorizeResult({required this.transaction, required this.triggerReason});

  /// Whether the authorization completed because the transaction status changed,
  /// as opposed to a polling timeout.
  bool get isStatusChanged => triggerReason == 'transaction-status-changed';
  bool get isMaxRetriesReached => triggerReason == 'max-retries-reached';
}

/// Error event
class PaymentWidgetErrorEvent extends PaymentWidgetEvent {
  final PaymentWidgetError error;

  const PaymentWidgetErrorEvent(this.error);

  factory PaymentWidgetErrorEvent._fromJson(Map<String, dynamic> json) =>
      PaymentWidgetErrorEvent(PaymentWidgetError.fromJson(json));
}

class PaymentWidgetError implements Exception {
  final String name;
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int? httpStatusCode;

  const PaymentWidgetError({
    required this.name,
    required this.code,
    required this.message,
    this.details,
    this.httpStatusCode,
  });

  factory PaymentWidgetError.fromJson(Map<String, dynamic> json) => PaymentWidgetError(
    name: switch (json['name']) {
      String name => name,
      _ => 'UnknownError',
    },
    code: switch (json['code']) {
      String code => code,
      _ => 'unknown',
    },
    message: switch (json['message']) {
      String msg => msg,
      _ => 'An unknown error occurred',
    },
    details: switch (json['details']) {
      Map<String, dynamic> d => d,
      _ => null,
    },
    httpStatusCode: switch (json['httpStatusCode']) {
      int code => code,
      _ => null,
    },
  );

  @override
  String toString() => 'PaymentWidgetError($code): $message';
}
