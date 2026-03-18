import 'dart:convert';

/// Session
/// Mirrors the response from Uphold's Travel Rule Create Session endpoint.
///
/// See: https://developer.uphold.com/rest-apis/widgets-api/travel-rule/create-session
class TravelRuleWidgetSession {
  final String url;
  final String token;
  final TravelRuleWidgetFlow flow;

  /// Context data for the flow (provider info, transaction params, etc.).
  final TravelRuleWidgetData data;

  const TravelRuleWidgetSession({required this.url, required this.token, required this.flow, required this.data});

  factory TravelRuleWidgetSession.fromJson(Map<String, dynamic> json) => switch (json) {
    {'url': String url, 'token': String token, 'flow': String flow, 'data': Map<String, dynamic> data} =>
      TravelRuleWidgetSession(
        url: url,
        token: token,
        flow: TravelRuleWidgetFlow.fromString(flow),
        data: TravelRuleWidgetData.fromJson(data),
      ),
    _ => throw FormatException('Invalid TravelRuleWidgetSession JSON: $json'),
  };

  Map<String, dynamic> toJson() => {'url': url, 'token': token, 'flow': flow.value, 'data': data.toJson()};
}

/// Flows
/// The two flows supported by the Travel Rule Widget.
enum TravelRuleWidgetFlow {
  depositForm('deposit-form'),
  withdrawalForm('withdrawal-form');

  const TravelRuleWidgetFlow(this.value);

  final String value;

  static TravelRuleWidgetFlow fromString(String value) => TravelRuleWidgetFlow.values.firstWhere(
    (f) => f.value == value,
    orElse: () => throw ArgumentError('Unknown TravelRuleWidgetFlow: $value'),
  );
}

/// Data included in the session, containing context for the flow.
class TravelRuleWidgetData {
  /// The travel rule provider (e.g. `'notabene'`).
  final String provider;

  /// Provider-specific parameters (init config, options, transaction details).
  final Map<String, dynamic> parameters;

  const TravelRuleWidgetData({required this.provider, required this.parameters});

  factory TravelRuleWidgetData.fromJson(Map<String, dynamic> json) => switch (json) {
    {'provider': String provider, 'parameters': Map<String, dynamic> parameters} => TravelRuleWidgetData(
      provider: provider,
      parameters: parameters,
    ),
    _ => throw FormatException('Invalid TravelRuleWidgetData JSON: $json'),
  };

  Map<String, dynamic> toJson() => {'provider': provider, 'parameters': parameters};
}

/// Widget options
class TravelRuleWidgetOptions {
  final bool debug;

  const TravelRuleWidgetOptions({this.debug = false});

  Map<String, dynamic> toJson() => {'debug': debug};
}

/// Events
/// Umbrella type for all events dispatched by the Travel Rule Widget.
sealed class TravelRuleWidgetEvent {
  const TravelRuleWidgetEvent();

  /// Deserialises a raw JSON string from the JavaScript bridge.
  factory TravelRuleWidgetEvent.fromMessage(String message) => switch (jsonDecode(message)) {
    {'type': 'ready'} => const TravelRuleWidgetReadyEvent(),
    {'type': 'complete', 'data': Map<String, dynamic> data} => TravelRuleWidgetCompleteEvent._fromJson(data),
    {'type': 'complete'} => TravelRuleWidgetCompleteEvent._fromJson({}),
    {'type': 'cancel'} => const TravelRuleWidgetCancelEvent(),
    {'type': 'error', 'data': Map<String, dynamic> data} => TravelRuleWidgetErrorEvent._fromJson(data),
    {'type': 'error'} => TravelRuleWidgetErrorEvent._fromJson({}),
    {'type': String type} => throw ArgumentError('Unknown TravelRuleWidgetEvent type: $type'),
    _ => throw const FormatException('Invalid TravelRuleWidgetEvent message'),
  };
}

class TravelRuleWidgetReadyEvent extends TravelRuleWidgetEvent {
  const TravelRuleWidgetReadyEvent();
}

class TravelRuleWidgetCancelEvent extends TravelRuleWidgetEvent {
  const TravelRuleWidgetCancelEvent();
}

/// Complete event
class TravelRuleWidgetCompleteEvent extends TravelRuleWidgetEvent {
  /// Opaque travel rule compliance data.
  ///
  /// Pass this as-is to your backend when resolving RFIs or creating transactions.
  final TravelRuleResult result;

  const TravelRuleWidgetCompleteEvent(this.result);

  factory TravelRuleWidgetCompleteEvent._fromJson(Map<String, dynamic> json) =>
      TravelRuleWidgetCompleteEvent(TravelRuleResult(data: json));
}

/// Opaque result from the Travel Rule form.
///
/// This should be forwarded to your backend as-is. Do not parse or modify it.
class TravelRuleResult {
  final Map<String, dynamic> data;
  const TravelRuleResult({required this.data});
}

/// Error event
class TravelRuleWidgetErrorEvent extends TravelRuleWidgetEvent {
  final TravelRuleWidgetError error;

  const TravelRuleWidgetErrorEvent(this.error);

  factory TravelRuleWidgetErrorEvent._fromJson(Map<String, dynamic> json) =>
      TravelRuleWidgetErrorEvent(TravelRuleWidgetError.fromJson(json));
}

class TravelRuleWidgetError implements Exception {
  final String name;
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int? httpStatusCode;

  const TravelRuleWidgetError({
    required this.name,
    required this.code,
    required this.message,
    this.details,
    this.httpStatusCode,
  });

  factory TravelRuleWidgetError.fromJson(Map<String, dynamic> json) => TravelRuleWidgetError(
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
  String toString() => 'TravelRuleWidgetError($code): $message';
}
