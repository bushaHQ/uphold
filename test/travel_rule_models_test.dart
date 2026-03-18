import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uphold/uphold.dart';

void main() {
  group('TravelRuleWidgetFlow', () {
    test('fromString resolves all known flows', () {
      expect(TravelRuleWidgetFlow.fromString('deposit-form'), TravelRuleWidgetFlow.depositForm);
      expect(TravelRuleWidgetFlow.fromString('withdrawal-form'), TravelRuleWidgetFlow.withdrawalForm);
    });

    test('fromString throws on unknown value', () {
      expect(() => TravelRuleWidgetFlow.fromString('invalid'), throwsA(isA<ArgumentError>()));
    });

    test('value getter returns correct string', () {
      expect(TravelRuleWidgetFlow.depositForm.value, 'deposit-form');
      expect(TravelRuleWidgetFlow.withdrawalForm.value, 'withdrawal-form');
    });
  });

  group('TravelRuleWidgetData', () {
    test('fromJson parses valid JSON', () {
      final data = TravelRuleWidgetData.fromJson({
        'provider': 'notabene',
        'parameters': {
          'init': {'authToken': 'tok_123'},
          'transaction': {'asset': 'XRP-XRP'},
        },
      });

      expect(data.provider, 'notabene');
      expect(data.parameters['init'], isA<Map>());
      expect((data.parameters['init'] as Map)['authToken'], 'tok_123');
    });

    test('fromJson throws FormatException on missing provider', () {
      expect(() => TravelRuleWidgetData.fromJson({'parameters': {}}), throwsA(isA<FormatException>()));
    });

    test('fromJson throws FormatException on missing parameters', () {
      expect(() => TravelRuleWidgetData.fromJson({'provider': 'notabene'}), throwsA(isA<FormatException>()));
    });

    test('fromJson throws FormatException on wrong types', () {
      expect(() => TravelRuleWidgetData.fromJson({'provider': 123, 'parameters': {}}), throwsA(isA<FormatException>()));
    });

    test('toJson round-trips correctly', () {
      const original = TravelRuleWidgetData(provider: 'notabene', parameters: {'key': 'value'});
      final json = original.toJson();

      expect(json, {
        'provider': 'notabene',
        'parameters': {'key': 'value'},
      });

      final restored = TravelRuleWidgetData.fromJson(json);
      expect(restored.provider, original.provider);
      expect(restored.parameters, original.parameters);
    });
  });

  group('TravelRuleWidgetSession', () {
    test('fromJson parses valid JSON', () {
      final session = TravelRuleWidgetSession.fromJson({
        'url': 'https://travel-rule.enterprise.uphold.com/',
        'token': 'tok_abc',
        'flow': 'deposit-form',
        'data': {
          'provider': 'notabene',
          'parameters': {'init': {}},
        },
      });

      expect(session.url, 'https://travel-rule.enterprise.uphold.com/');
      expect(session.token, 'tok_abc');
      expect(session.flow, TravelRuleWidgetFlow.depositForm);
      expect(session.data.provider, 'notabene');
    });

    test('fromJson throws FormatException on missing fields', () {
      expect(() => TravelRuleWidgetSession.fromJson({'url': 'https://example.com'}), throwsA(isA<FormatException>()));
    });

    test('fromJson throws FormatException on missing data field', () {
      expect(
        () => TravelRuleWidgetSession.fromJson({'url': 'https://example.com', 'token': 'tok', 'flow': 'deposit-form'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws FormatException on wrong types', () {
      expect(
        () => TravelRuleWidgetSession.fromJson({
          'url': 123,
          'token': 'tok',
          'flow': 'deposit-form',
          'data': {'provider': 'notabene', 'parameters': {}},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws on unknown flow value', () {
      expect(
        () => TravelRuleWidgetSession.fromJson({
          'url': 'https://example.com',
          'token': 'tok',
          'flow': 'unknown-flow',
          'data': {'provider': 'notabene', 'parameters': {}},
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toJson round-trips correctly', () {
      const original = TravelRuleWidgetSession(
        url: 'https://example.com',
        token: 'tok_abc',
        flow: TravelRuleWidgetFlow.withdrawalForm,
        data: TravelRuleWidgetData(provider: 'notabene', parameters: {'key': 'val'}),
      );
      final json = original.toJson();

      expect(json, {
        'url': 'https://example.com',
        'token': 'tok_abc',
        'flow': 'withdrawal-form',
        'data': {
          'provider': 'notabene',
          'parameters': {'key': 'val'},
        },
      });

      final restored = TravelRuleWidgetSession.fromJson(json);
      expect(restored.url, original.url);
      expect(restored.token, original.token);
      expect(restored.flow, original.flow);
      expect(restored.data.provider, original.data.provider);
    });
  });

  group('TravelRuleWidgetOptions', () {
    test('toJson with defaults', () {
      const opts = TravelRuleWidgetOptions();
      expect(opts.toJson(), {'debug': false});
    });

    test('toJson with debug true', () {
      const opts = TravelRuleWidgetOptions(debug: true);
      expect(opts.toJson(), {'debug': true});
    });
  });

  group('TravelRuleWidgetEvent.fromMessage', () {
    test('parses ready event', () {
      final event = TravelRuleWidgetEvent.fromMessage('{"type":"ready"}');
      expect(event, isA<TravelRuleWidgetReadyEvent>());
    });

    test('parses cancel event', () {
      final event = TravelRuleWidgetEvent.fromMessage('{"type":"cancel"}');
      expect(event, isA<TravelRuleWidgetCancelEvent>());
    });

    test('parses complete event with data', () {
      final message = jsonEncode({
        'type': 'complete',
        'data': {
          'originator': {'name': 'John Doe'},
          'beneficiary': {'name': 'Jane Doe'},
        },
      });
      final event = TravelRuleWidgetEvent.fromMessage(message);
      expect(event, isA<TravelRuleWidgetCompleteEvent>());
      final complete = event as TravelRuleWidgetCompleteEvent;
      expect(complete.result.data['originator'], isA<Map>());
    });

    test('parses complete event without data', () {
      final event = TravelRuleWidgetEvent.fromMessage('{"type":"complete"}');
      expect(event, isA<TravelRuleWidgetCompleteEvent>());
      final complete = event as TravelRuleWidgetCompleteEvent;
      expect(complete.result.data, isEmpty);
    });

    test('parses error event with data', () {
      final message = jsonEncode({
        'type': 'error',
        'data': {'name': 'ValidationError', 'code': 'validation_failed', 'message': 'Bad input'},
      });
      final event = TravelRuleWidgetEvent.fromMessage(message);
      expect(event, isA<TravelRuleWidgetErrorEvent>());
      final errorEvent = event as TravelRuleWidgetErrorEvent;
      expect(errorEvent.error.name, 'ValidationError');
      expect(errorEvent.error.code, 'validation_failed');
      expect(errorEvent.error.message, 'Bad input');
    });

    test('parses error event without data', () {
      final event = TravelRuleWidgetEvent.fromMessage('{"type":"error"}');
      expect(event, isA<TravelRuleWidgetErrorEvent>());
      final errorEvent = event as TravelRuleWidgetErrorEvent;
      expect(errorEvent.error.name, 'UnknownError');
      expect(errorEvent.error.code, 'unknown');
      expect(errorEvent.error.message, 'An unknown error occurred');
    });

    test('throws ArgumentError on unknown event type', () {
      expect(() => TravelRuleWidgetEvent.fromMessage('{"type":"foo"}'), throwsA(isA<ArgumentError>()));
    });

    test('throws FormatException on invalid message', () {
      expect(() => TravelRuleWidgetEvent.fromMessage('{"invalid":true}'), throwsA(isA<FormatException>()));
    });

    test('throws FormatException on non-JSON', () {
      expect(() => TravelRuleWidgetEvent.fromMessage('not json'), throwsA(isA<FormatException>()));
    });
  });

  group('TravelRuleResult', () {
    test('holds opaque data', () {
      const result = TravelRuleResult(data: {'originator': 'John', 'txRef': 'abc123'});
      expect(result.data['originator'], 'John');
      expect(result.data['txRef'], 'abc123');
    });

    test('holds empty data', () {
      const result = TravelRuleResult(data: {});
      expect(result.data, isEmpty);
    });
  });

  group('TravelRuleWidgetError', () {
    test('fromJson parses all fields', () {
      final error = TravelRuleWidgetError.fromJson({
        'name': 'ValidationError',
        'code': 'validation_failed',
        'message': 'Invalid input',
        'details': {'field': 'name'},
        'httpStatusCode': 422,
      });
      expect(error.name, 'ValidationError');
      expect(error.code, 'validation_failed');
      expect(error.message, 'Invalid input');
      expect(error.details, {'field': 'name'});
      expect(error.httpStatusCode, 422);
    });

    test('fromJson uses defaults for missing fields', () {
      final error = TravelRuleWidgetError.fromJson({});
      expect(error.name, 'UnknownError');
      expect(error.code, 'unknown');
      expect(error.message, 'An unknown error occurred');
      expect(error.details, isNull);
      expect(error.httpStatusCode, isNull);
    });

    test('fromJson handles wrong types gracefully', () {
      final error = TravelRuleWidgetError.fromJson({
        'name': 123,
        'code': true,
        'message': [],
        'details': 'not a map',
        'httpStatusCode': '500',
      });
      expect(error.name, 'UnknownError');
      expect(error.code, 'unknown');
      expect(error.message, 'An unknown error occurred');
      expect(error.details, isNull);
      expect(error.httpStatusCode, isNull);
    });

    test('toString formats correctly', () {
      const error = TravelRuleWidgetError(name: 'TestError', code: 'test_code', message: 'Test message');
      expect(error.toString(), 'TravelRuleWidgetError(test_code): Test message');
    });

    test('implements Exception', () {
      const error = TravelRuleWidgetError(name: 'E', code: 'c', message: 'm');
      expect(error, isA<Exception>());
    });
  });
}
