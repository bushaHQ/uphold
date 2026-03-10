import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uphold_payment_widget/uphold_payment_widget.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Uphold Payment Widget Demo',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
    home: const HomePage(),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Uphold Widget Demo')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: () => _openFlow(context, PaymentWidgetFlow.selectForDeposit),
            child: const Text('Deposit'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _openFlow(context, PaymentWidgetFlow.selectForWithdrawal),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    ),
  );

  void _openFlow(BuildContext context, PaymentWidgetFlow flow) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentPage(flow: flow)));
  }
}

class PaymentPage extends StatefulWidget {
  final PaymentWidgetFlow flow;

  const PaymentPage({super.key, required this.flow});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  PaymentWidgetSession? _session;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSession();
  }

  Future<void> _fetchSession() async {
    try {
      final response = await http.post(
        Uri.parse('https://your-backend.example.com/api/uphold/sessions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'flow': widget.flow.value}),
      );

      if (response.statusCode case < 200 || >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final session = switch (jsonDecode(response.body)) {
        {'session': Map<String, dynamic> data} => PaymentWidgetSession.fromJson(data),
        _ => throw const FormatException('Missing "session" key in response'),
      };

      if (mounted) setState(() => _session = session);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onComplete(PaymentWidgetResult result) {
    switch (result) {
      case ExternalAccountResult(:final selection):
        print('Saved account selected: $selection');

      case DepositMethodResult(:final depositMethod, :final account):
        final type = depositMethod['type'];
        print('Deposit via $type → account ${account['id']}');

      case CryptoNetworkResult(:final network, :final address, :final reference):
        print('Withdraw to $network @ $address (ref: $reference)');

      case AuthorizeResult(:final transaction, :final triggerReason):
        final status = transaction['status'];
        print('Authorize complete ($triggerReason): tx status = $status');

      case UnknownResult(:final raw):
        print('Unknown: $raw');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flow completed')));
      Navigator.of(context).pop();
    }
  }

  void _onCancel() {
    if (mounted) Navigator.of(context).pop();
  }

  void _onError(PaymentWidgetError error) {
    print('Widget error [${error.code}]: ${error.message}');

    if (error.code == 'entity_not_found') {
      // Session / quote expired → retry.
      setState(() {
        _session = null;
        _error = null;
      });
      _fetchSession();
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.flow) {
      PaymentWidgetFlow.selectForDeposit => 'Deposit',
      PaymentWidgetFlow.selectForWithdrawal => 'Withdraw',
      PaymentWidgetFlow.authorize => 'Authorize',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() => switch ((_session, _error)) {
    (_, String error) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() => _error = null);
                _fetchSession();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
    (PaymentWidgetSession session, _) => UpholdPaymentWidget(
      config: UpholdPaymentWidgetConfig(
        session: session,
        options: const PaymentWidgetOptions(
          debug: true,
          paymentMethods: [
            CardPaymentMethod(),
            BankPaymentMethod(),
            CryptoPaymentMethod(assets: PaymentAssetFilter.include(['BTC', 'ETH', 'XRP'])),
          ],
        ),
      ),
      onReady: () => print('Widget ready'),
      onComplete: _onComplete,
      onCancel: _onCancel,
      onError: _onError,
    ),
    _ => const Center(child: CircularProgressIndicator.adaptive()),
  };
}
