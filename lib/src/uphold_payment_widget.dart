import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import 'models.dart';

/// Configuration for the [UpholdPaymentWidget].
class UpholdPaymentWidgetConfig {
  /// Session obtained from Uphold's Create Session endpoint via your backend.
  final PaymentWidgetSession session;

  /// Optional display / filtering options.
  final PaymentWidgetOptions? options;

  const UpholdPaymentWidgetConfig({required this.session, this.options});
}

/// Embeds the Uphold Payment Widget inside a Flutter widget tree.
///
/// ```dart
/// UpholdPaymentWidget(
///   config: UpholdPaymentWidgetConfig(session: session),
///   onComplete: (result) => handleResult(result),
///   onCancel: () => Navigator.pop(context),
///   onError: (err) => showError(err),
/// )
/// ```
class UpholdPaymentWidget extends StatefulWidget {
  final UpholdPaymentWidgetConfig config;

  /// Called when the widget has loaded and is interactive.
  final VoidCallback? onReady;

  /// Called when the payment flow completes.
  final ValueChanged<PaymentWidgetResult>? onComplete;

  /// Called when the user dismisses the flow.
  final VoidCallback? onCancel;

  /// Called on unrecoverable errors.
  final ValueChanged<PaymentWidgetError>? onError;

  /// Shown while the WebView + SDK are loading.
  final WidgetBuilder? loadingBuilder;

  const UpholdPaymentWidget({
    super.key,
    required this.config,
    this.onReady,
    this.onComplete,
    this.onCancel,
    this.onError,
    this.loadingBuilder,
  });

  @override
  State<UpholdPaymentWidget> createState() => _UpholdPaymentWidgetState();
}

class _UpholdPaymentWidgetState extends State<UpholdPaymentWidget> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _initialized = false;

  // Package asset paths — resolved via the `packages/` prefix so they
  // work from any consuming app.
  static const _htmlAsset = 'packages/uphold_payment_widget/assets/payment_widget.html';
  static const _sdkAsset = 'packages/uphold_payment_widget/assets/payment_widget_sdk.js';

  @override
  void initState() {
    super.initState();
    _setupController();
    _loadAssets();
  }

  void _setupController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.navigate,
          onPageFinished: (_) {
            if (!_initialized) {
              _initialized = true;
              _injectSession();
            }
          },
        ),
      )
      ..addJavaScriptChannel('PaymentWidgetBridge', onMessageReceived: _onBridgeMessage);
  }

  Future<void> _loadAssets() async {
    try {
      final results = await Future.wait([rootBundle.loadString(_htmlAsset), rootBundle.loadString(_sdkAsset)]);

      final html = results[0];
      final sdkJs = results[1];

      final assembledHtml = html.replaceFirst('<!--INJECT_SDK-->', '<script>\n$sdkJs\n</script>');

      await _controller.loadHtmlString(assembledHtml);
    } catch (e) {
      widget.onError?.call(
        PaymentWidgetError(
          name: 'AssetLoadError',
          code: 'asset_load_failed',
          message: 'Could not load Payment Widget assets: $e',
        ),
      );
    }
  }

  Future<void> _injectSession() async {
    final sessionJson = jsonEncode(widget.config.session.toJson());
    final optionsJson = switch (widget.config.options) {
      final options? => jsonEncode(options.toJson()),
      _ => 'null',
    };

    await _controller.runJavaScript("initWidget('${_escapeJs(sessionJson)}', '${_escapeJs(optionsJson)}');");
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    try {
      switch (PaymentWidgetEvent.fromMessage(message.message)) {
        case PaymentWidgetReadyEvent():
          if (mounted) setState(() => _loading = false);
          widget.onReady?.call();

        case PaymentWidgetCompleteEvent(result: final result):
          widget.onComplete?.call(result);

        case PaymentWidgetCancelEvent():
          widget.onCancel?.call();

        case PaymentWidgetErrorEvent(error: final error):
          widget.onError?.call(error);
      }
    } catch (e) {
      debugPrint('[UpholdPaymentWidget] Bridge parse error: $e');
    }
  }

  static String _escapeJs(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n').replaceAll('\r', '\\r');

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      WebViewWidget(controller: _controller),
      if (_loading) widget.loadingBuilder?.call(context) ?? const Center(child: CircularProgressIndicator.adaptive()),
    ],
  );
}
