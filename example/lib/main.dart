import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uphold/uphold.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Uphold Payment Widget Demo',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
    darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green, brightness: Brightness.dark),
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

Future<PaymentWidgetSession> fetchSession(PaymentWidgetFlow flow) async {
  final response = await http.post(
    Uri.parse('URL_OF_YOUR_BACKEND_ENDPOINT'), // Replace with your backend endpoint that creates a session
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'flow': flow.value}),
  );

  if (response.statusCode case < 200 || >= 300) {
    throw Exception('HTTP ${response.statusCode}');
  }

  return switch (jsonDecode(response.body)) {
    {'session': Map<String, dynamic> data} => PaymentWidgetSession.fromJson(data),
    _ => throw const FormatException('Missing "session" key in response'),
  };
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

  final _widgetController = UpholdPaymentWidgetController();

  @override
  void initState() {
    super.initState();
    _fetchSession();
  }

  @override
  void dispose() {
    _widgetController.dispose();
    super.dispose();
  }

  Future<void> _fetchSession() async {
    try {
      final session = await fetchSession(widget.flow);
      if (mounted) setState(() => _session = session);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onComplete(PaymentWidgetResult result) {
    switch (result) {
      case ExternalAccountResult(:final selection):
        debugPrint('Saved account selected: $selection');

      case DepositMethodResult(:final depositMethod, :final account):
        final type = depositMethod['type'];
        debugPrint('Deposit via $type → account ${account['id']}');

      case CryptoNetworkResult(:final network, :final address, :final reference):
        debugPrint('Withdraw to $network @ $address (ref: $reference)');

      case AuthorizeResult(:final transaction, :final triggerReason):
        final status = transaction['status'];
        debugPrint('Authorize complete ($triggerReason): tx status = $status');

      case UnknownResult(:final raw):
        debugPrint('Unknown: $raw');
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
    debugPrint('Widget error [${error.code}]: ${error.message}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: _buildBody(context)));

  Widget _buildBody(BuildContext context) => switch ((_session, _error)) {
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        loadingTimeout: const Duration(seconds: 20),
        locale: 'en-US',
        enableWebViewDebugging: true,

        // Optional navigation filtering. Returning `true` allows all by default.
        // Block a known problematic domain as an example:
        // navigationPolicy: (url) => !url.contains('malicious.example.com'),
      ),
      sessionProvider: () => fetchSession(widget.flow),
      controller: _widgetController,
      onReady: () => debugPrint('Widget ready'),
      onComplete: _onComplete,
      onCancel: _onCancel,
      onError: _onError,
      onDispose: () => debugPrint('Widget disposed'),
      loadingBuilder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator.adaptive(), SizedBox(height: 12), Text('Loading payment options...')],
        ),
      ),
      errorBuilder: (context, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(error.message, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Code: ${error.code}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => _widgetController.reload(), child: const Text('Retry')),
            ],
          ),
        ),
      ),
    ),
    _ => const Center(child: CircularProgressIndicator.adaptive()),
  };
}
