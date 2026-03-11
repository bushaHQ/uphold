import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uphold/uphold.dart';

void main() {
  group('PaymentWidgetFlow', () {
    test('fromString resolves all known flows', () {
      expect(PaymentWidgetFlow.fromString('select-for-deposit'), PaymentWidgetFlow.selectForDeposit);
      expect(PaymentWidgetFlow.fromString('select-for-withdrawal'), PaymentWidgetFlow.selectForWithdrawal);
      expect(PaymentWidgetFlow.fromString('authorize'), PaymentWidgetFlow.authorize);
    });

    test('fromString throws on unknown value', () {
      expect(() => PaymentWidgetFlow.fromString('invalid'), throwsA(isA<ArgumentError>()));
    });

    test('value getter returns correct string', () {
      expect(PaymentWidgetFlow.selectForDeposit.value, 'select-for-deposit');
      expect(PaymentWidgetFlow.selectForWithdrawal.value, 'select-for-withdrawal');
      expect(PaymentWidgetFlow.authorize.value, 'authorize');
    });
  });

  group('PaymentWidgetSession', () {
    test('fromJson parses valid JSON', () {
      final session = PaymentWidgetSession.fromJson({
        'url': 'https://example.com',
        'token': 'tok_123',
        'flow': 'authorize',
      });

      expect(session.url, 'https://example.com');
      expect(session.token, 'tok_123');
      expect(session.flow, PaymentWidgetFlow.authorize);
    });

    test('fromJson throws FormatException on missing fields', () {
      expect(() => PaymentWidgetSession.fromJson({'url': 'https://example.com'}), throwsA(isA<FormatException>()));
    });

    test('fromJson throws FormatException on wrong types', () {
      expect(
        () => PaymentWidgetSession.fromJson({'url': 123, 'token': 'tok', 'flow': 'authorize'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws on unknown flow value', () {
      expect(
        () => PaymentWidgetSession.fromJson({'url': 'https://example.com', 'token': 'tok', 'flow': 'unknown-flow'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toJson round-trips correctly', () {
      const original = PaymentWidgetSession(
        url: 'https://example.com',
        token: 'tok_abc',
        flow: PaymentWidgetFlow.selectForDeposit,
      );
      final json = original.toJson();

      expect(json, {'url': 'https://example.com', 'token': 'tok_abc', 'flow': 'select-for-deposit'});

      final restored = PaymentWidgetSession.fromJson(json);
      expect(restored.url, original.url);
      expect(restored.token, original.token);
      expect(restored.flow, original.flow);
    });
  });

  group('PaymentMethodOption', () {
    test('CardPaymentMethod toJson', () {
      const card = CardPaymentMethod();
      expect(card.toJson(), {'type': 'card'});
    });

    test('BankPaymentMethod toJson without assets', () {
      const bank = BankPaymentMethod();
      expect(bank.toJson(), {'type': 'bank'});
    });

    test('BankPaymentMethod toJson with include filter', () {
      const bank = BankPaymentMethod(assets: PaymentAssetFilter.include(['USD', 'EUR']));
      expect(bank.toJson(), {
        'type': 'bank',
        'assets': {
          'include': ['USD', 'EUR'],
        },
      });
    });

    test('BankPaymentMethod toJson with exclude filter', () {
      const bank = BankPaymentMethod(assets: PaymentAssetFilter.exclude(['BRL']));
      expect(bank.toJson(), {
        'type': 'bank',
        'assets': {
          'exclude': ['BRL'],
        },
      });
    });

    test('CryptoPaymentMethod toJson without assets', () {
      const crypto = CryptoPaymentMethod();
      expect(crypto.toJson(), {'type': 'crypto'});
    });

    test('CryptoPaymentMethod toJson with include filter', () {
      const crypto = CryptoPaymentMethod(assets: PaymentAssetFilter.include(['BTC', 'ETH']));
      expect(crypto.toJson(), {
        'type': 'crypto',
        'assets': {
          'include': ['BTC', 'ETH'],
        },
      });
    });

    test('CryptoPaymentMethod toJson with exclude filter', () {
      const crypto = CryptoPaymentMethod(assets: PaymentAssetFilter.exclude(['DOGE']));
      expect(crypto.toJson(), {
        'type': 'crypto',
        'assets': {
          'exclude': ['DOGE'],
        },
      });
    });
  });

  group('PaymentAssetFilter', () {
    test('include constructor sets include only', () {
      const filter = PaymentAssetFilter.include(['BTC']);
      expect(filter.include, ['BTC']);
      expect(filter.exclude, isNull);
    });

    test('exclude constructor sets exclude only', () {
      const filter = PaymentAssetFilter.exclude(['ETH']);
      expect(filter.include, isNull);
      expect(filter.exclude, ['ETH']);
    });

    test('toJson with include only', () {
      const filter = PaymentAssetFilter.include(['USD']);
      expect(filter.toJson(), {
        'include': ['USD'],
      });
    });

    test('toJson with exclude only', () {
      const filter = PaymentAssetFilter.exclude(['BRL']);
      expect(filter.toJson(), {
        'exclude': ['BRL'],
      });
    });

    test('default constructor with neither', () {
      const filter = PaymentAssetFilter();
      expect(filter.include, isNull);
      expect(filter.exclude, isNull);
      expect(filter.toJson(), <String, dynamic>{});
    });
  });

  group('PaymentWidgetOptions', () {
    test('toJson with defaults', () {
      const opts = PaymentWidgetOptions();
      expect(opts.toJson(), {'debug': false});
    });

    test('toJson with debug true', () {
      const opts = PaymentWidgetOptions(debug: true);
      expect(opts.toJson(), {'debug': true});
    });

    test('toJson with payment methods', () {
      const opts = PaymentWidgetOptions(
        debug: false,
        paymentMethods: [
          CardPaymentMethod(),
          BankPaymentMethod(assets: PaymentAssetFilter.include(['USD'])),
          CryptoPaymentMethod(),
        ],
      );
      final json = opts.toJson();

      expect(json['debug'], false);
      expect(json['paymentMethods'], isList);
      final methods = json['paymentMethods'] as List;
      expect(methods.length, 3);
      expect(methods[0], {'type': 'card'});
      expect(methods[1], {
        'type': 'bank',
        'assets': {
          'include': ['USD'],
        },
      });
      expect(methods[2], {'type': 'crypto'});
    });

    test('toJson without payment methods omits the key', () {
      const opts = PaymentWidgetOptions();
      final json = opts.toJson();
      expect(json.containsKey('paymentMethods'), isFalse);
    });
  });

  group('PaymentWidgetEvent.fromMessage', () {
    test('parses ready event', () {
      final event = PaymentWidgetEvent.fromMessage('{"type":"ready"}');
      expect(event, isA<PaymentWidgetReadyEvent>());
    });

    test('parses cancel event', () {
      final event = PaymentWidgetEvent.fromMessage('{"type":"cancel"}');
      expect(event, isA<PaymentWidgetCancelEvent>());
    });

    test('parses complete event with data', () {
      final message = jsonEncode({
        'type': 'complete',
        'data': {
          'via': 'external-account',
          'selection': {'id': 'acct_1'},
        },
      });
      final event = PaymentWidgetEvent.fromMessage(message);
      expect(event, isA<PaymentWidgetCompleteEvent>());
      final complete = event as PaymentWidgetCompleteEvent;
      expect(complete.result, isA<ExternalAccountResult>());
    });

    test('parses complete event without data', () {
      final event = PaymentWidgetEvent.fromMessage('{"type":"complete"}');
      expect(event, isA<PaymentWidgetCompleteEvent>());
      final complete = event as PaymentWidgetCompleteEvent;
      expect(complete.result, isA<UnknownResult>());
    });

    test('parses error event with data', () {
      final message = jsonEncode({
        'type': 'error',
        'data': {'name': 'TestError', 'code': 'test_err', 'message': 'Something went wrong'},
      });
      final event = PaymentWidgetEvent.fromMessage(message);
      expect(event, isA<PaymentWidgetErrorEvent>());
      final errorEvent = event as PaymentWidgetErrorEvent;
      expect(errorEvent.error.name, 'TestError');
      expect(errorEvent.error.code, 'test_err');
      expect(errorEvent.error.message, 'Something went wrong');
    });

    test('parses error event without data', () {
      final event = PaymentWidgetEvent.fromMessage('{"type":"error"}');
      expect(event, isA<PaymentWidgetErrorEvent>());
      final errorEvent = event as PaymentWidgetErrorEvent;
      expect(errorEvent.error.name, 'UnknownError');
      expect(errorEvent.error.code, 'unknown');
      expect(errorEvent.error.message, 'An unknown error occurred');
    });

    test('throws ArgumentError on unknown event type', () {
      expect(() => PaymentWidgetEvent.fromMessage('{"type":"foo"}'), throwsA(isA<ArgumentError>()));
    });

    test('throws FormatException on invalid message', () {
      expect(() => PaymentWidgetEvent.fromMessage('{"invalid":true}'), throwsA(isA<FormatException>()));
    });

    test('throws FormatException on non-JSON', () {
      expect(() => PaymentWidgetEvent.fromMessage('not json'), throwsA(isA<FormatException>()));
    });
  });

  group('PaymentWidgetResult.fromJson', () {
    test('parses ExternalAccountResult', () {
      final result = PaymentWidgetResult.fromJson({
        'via': 'external-account',
        'selection': {'id': 'acct_1', 'type': 'card'},
      });
      expect(result, isA<ExternalAccountResult>());
      final external = result as ExternalAccountResult;
      expect(external.selection['id'], 'acct_1');
      expect(external.selection['type'], 'card');
    });

    test('parses DepositMethodResult', () {
      final result = PaymentWidgetResult.fromJson({
        'via': 'deposit-method',
        'selection': {
          'depositMethod': {'type': 'wire', 'details': {}},
          'account': {'id': 'acc_1'},
        },
      });
      expect(result, isA<DepositMethodResult>());
      final deposit = result as DepositMethodResult;
      expect(deposit.depositMethod['type'], 'wire');
      expect(deposit.account['id'], 'acc_1');
    });

    test('parses CryptoNetworkResult with reference', () {
      final result = PaymentWidgetResult.fromJson({
        'via': 'crypto-network',
        'selection': {'network': 'xrp-ledger', 'address': 'rXxx123', 'reference': 'dt_456'},
      });
      expect(result, isA<CryptoNetworkResult>());
      final crypto = result as CryptoNetworkResult;
      expect(crypto.network, 'xrp-ledger');
      expect(crypto.address, 'rXxx123');
      expect(crypto.reference, 'dt_456');
    });

    test('parses CryptoNetworkResult without reference (null)', () {
      final result = PaymentWidgetResult.fromJson({
        'via': 'crypto-network',
        'selection': {'network': 'bitcoin', 'address': 'bc1q_addr', 'reference': null},
      });
      expect(result, isA<CryptoNetworkResult>());
      final crypto = result as CryptoNetworkResult;
      expect(crypto.network, 'bitcoin');
      expect(crypto.address, 'bc1q_addr');
      expect(crypto.reference, isNull);
    });

    test('parses AuthorizeResult', () {
      final result = PaymentWidgetResult.fromJson({
        'transaction': {'id': 'tx_1', 'status': 'completed'},
        'trigger': {'reason': 'transaction-status-changed'},
      });
      expect(result, isA<AuthorizeResult>());
      final auth = result as AuthorizeResult;
      expect(auth.transaction['id'], 'tx_1');
      expect(auth.triggerReason, 'transaction-status-changed');
    });

    test('returns UnknownResult for unrecognized structure', () {
      final raw = {'via': 'future-payment-type', 'foo': 'bar'};
      final result = PaymentWidgetResult.fromJson(raw);
      expect(result, isA<UnknownResult>());
      expect((result as UnknownResult).raw, raw);
    });

    test('returns UnknownResult for empty map', () {
      final result = PaymentWidgetResult.fromJson({});
      expect(result, isA<UnknownResult>());
    });
  });

  group('AuthorizeResult', () {
    test('isStatusChanged is true when reason matches', () {
      const result = AuthorizeResult(transaction: {'id': 'tx_1'}, triggerReason: 'transaction-status-changed');
      expect(result.isStatusChanged, isTrue);
      expect(result.isMaxRetriesReached, isFalse);
    });

    test('isMaxRetriesReached is true when reason matches', () {
      const result = AuthorizeResult(transaction: {'id': 'tx_1'}, triggerReason: 'max-retries-reached');
      expect(result.isStatusChanged, isFalse);
      expect(result.isMaxRetriesReached, isTrue);
    });

    test('both are false for other reasons', () {
      const result = AuthorizeResult(transaction: {'id': 'tx_1'}, triggerReason: 'some-other-reason');
      expect(result.isStatusChanged, isFalse);
      expect(result.isMaxRetriesReached, isFalse);
    });
  });

  group('PaymentWidgetError', () {
    test('fromJson parses all fields', () {
      final error = PaymentWidgetError.fromJson({
        'name': 'ValidationError',
        'code': 'validation_failed',
        'message': 'Invalid amount',
        'details': {'field': 'amount'},
        'httpStatusCode': 422,
      });
      expect(error.name, 'ValidationError');
      expect(error.code, 'validation_failed');
      expect(error.message, 'Invalid amount');
      expect(error.details, {'field': 'amount'});
      expect(error.httpStatusCode, 422);
    });

    test('fromJson uses defaults for missing fields', () {
      final error = PaymentWidgetError.fromJson({});
      expect(error.name, 'UnknownError');
      expect(error.code, 'unknown');
      expect(error.message, 'An unknown error occurred');
      expect(error.details, isNull);
      expect(error.httpStatusCode, isNull);
    });

    test('fromJson handles wrong types gracefully', () {
      final error = PaymentWidgetError.fromJson({
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
      const error = PaymentWidgetError(name: 'TestError', code: 'test_code', message: 'Test message');
      expect(error.toString(), 'PaymentWidgetError(test_code): Test message');
    });

    test('implements Exception', () {
      const error = PaymentWidgetError(name: 'E', code: 'c', message: 'm');
      expect(error, isA<Exception>());
    });
  });
}
