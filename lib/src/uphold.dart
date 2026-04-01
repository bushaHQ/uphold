import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'models.dart';

/// Callback that returns a fresh [PaymentWidgetSession].
///
/// Used by [UpholdPaymentWidget.sessionProvider] to transparently refresh
/// expired sessions without rebuilding the widget tree.
typedef SessionProvider = Future<PaymentWidgetSession> Function();

/// Callback that decides whether a navigation request should be allowed.
///
/// Return `true` to allow, `false` to block. Receives the target URL.
typedef NavigationPolicy = bool Function(String url);

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Programmatic handle for an [UpholdPaymentWidget] instance.
///
/// ```dart
/// final controller = UpholdPaymentWidgetController();
///
/// UpholdPaymentWidget(controller: controller, ...);
///
/// // Later:
/// controller.reload();   // re-inject session
/// controller.dispose();  // tear down
/// ```
class UpholdPaymentWidgetController extends ChangeNotifier {
  _UpholdPaymentWidgetState? _state;

  void _attach(_UpholdPaymentWidgetState state) => _state = state;
  void _detach() => _state = null;

  /// Whether the controller is currently attached to a live widget.
  bool get isAttached => _state != null;

  /// Re-injects the current session into the WebView.
  ///
  /// Useful after a session refresh without rebuilding the widget.
  Future<void> reload() async => _state?._reloadSession();

  @override
  void dispose() {
    _state = null;
    super.dispose();
  }
}

/// Configuration for the [UpholdPaymentWidget].
class UpholdPaymentWidgetConfig {
  /// Session obtained from Uphold's Create Session endpoint via your backend.
  final PaymentWidgetSession session;

  /// Optional display / filtering options.
  final PaymentWidgetOptions? options;

  /// Background color applied to the WebView before content loads.
  ///
  /// Defaults to transparent. Set this to match your app's scaffold color
  /// (especially in dark mode) to avoid the white flash.
  final Color backgroundColor;

  /// Locale string passed to the SDK (e.g. `'en-US'`, `'pt-BR'`).
  ///
  /// When `null` the SDK uses its own default.
  final String? locale;

  /// Maximum time to wait for the `ready` event before emitting a timeout error.
  ///
  /// Defaults to 30 seconds. Set to `null` to disable.
  final Duration? loadingTimeout;

  /// Enables WebView remote debugging.
  ///
  /// On Android this calls `AndroidWebViewController.enableDebugging(true)`.
  /// On iOS, `WKWebView` inspection is enabled automatically when the app is
  /// run from Xcode with a debugger attached.
  ///
  /// Defaults to `true` in debug mode, `false` in release.
  final bool? enableWebViewDebugging;

  /// Optional policy for navigation requests inside the WebView.
  ///
  /// Return `true` to allow, `false` to block. When `null`, all navigation
  /// is allowed (needed for 3DS card auth redirects to arbitrary bank domains).
  final NavigationPolicy? navigationPolicy;

  const UpholdPaymentWidgetConfig({
    required this.session,
    this.options,
    this.backgroundColor = Colors.transparent,
    this.locale,
    this.loadingTimeout = const Duration(seconds: 30),
    this.enableWebViewDebugging,
    this.navigationPolicy,
  });
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
  /// Override for how assembled HTML is loaded into the WebView.
  ///
  /// Defaults to writing a temp file and using [WebViewController.loadFile]
  /// to work around a WKWebView bug with [WebViewController.loadHtmlString].
  @visibleForTesting
  static Future<void> Function(WebViewController controller, String html)? htmlLoaderOverride;

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

  /// Shown when the widget enters an error state.
  ///
  /// Receives the [PaymentWidgetError] for contextual UI.
  /// When `null`, errors are only forwarded via [onError].
  final Widget Function(BuildContext context, PaymentWidgetError error)? errorBuilder;

  /// Provides a fresh session when the current one expires.
  ///
  /// When set, the widget automatically calls this on `entity_not_found`
  /// errors and re-initializes without consumer intervention.
  final SessionProvider? sessionProvider;

  /// Optional controller for programmatic access (reload, dispose).
  final UpholdPaymentWidgetController? controller;

  /// Called when the widget is about to be disposed.
  final VoidCallback? onDispose;

  const UpholdPaymentWidget({
    super.key,
    required this.config,
    this.onReady,
    this.onComplete,
    this.onCancel,
    this.onError,
    this.loadingBuilder,
    this.errorBuilder,
    this.sessionProvider,
    this.controller,
    this.onDispose,
  });

  @override
  State<UpholdPaymentWidget> createState() => _UpholdPaymentWidgetState();
}

enum _WidgetPhase { loading, ready, error }

class _UpholdPaymentWidgetState extends State<UpholdPaymentWidget> {
  late WebViewController _controller;
  _WidgetPhase _phase = _WidgetPhase.loading;
  PaymentWidgetError? _currentError;
  bool _initialized = false;
  Timer? _timeoutTimer;
  late PaymentWidgetSession _activeSession;
  Directory? _tempDir;

  static const _htmlAsset = 'packages/uphold/assets/payment_widget.html';
  static const _sdkAsset = 'packages/uphold/assets/payment_widget_sdk.js';

  @override
  void initState() {
    super.initState();
    _activeSession = widget.config.session;
    widget.controller?._attach(this);
    _enableDebugging();
    _setupController();
    _loadAssets();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _tempDir?.delete(recursive: true).ignore();
    widget.controller?._detach();
    widget.onDispose?.call();
    super.dispose();
  }

  void _enableDebugging() {
    final shouldDebug = widget.config.enableWebViewDebugging ?? kDebugMode;
    if (!shouldDebug) return;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        AndroidWebViewController.enableDebugging(true);
      case TargetPlatform.iOS:
        debugPrint('[UpholdPaymentWidget] WebView debugging enabled (iOS)');
      default:
        debugPrint('[UpholdPaymentWidget] WebView debugging is not supported on this platform.');
    }
  }

  void _setupController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.config.backgroundColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (widget.config.navigationPolicy case final policy?) {
              return policy(request.url) ? NavigationDecision.navigate : NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
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

      final bgColor = widget.config.backgroundColor;
      final colorScheme = _isDark(bgColor) ? 'dark' : 'light';
      final cssColor = _colorToCss(bgColor);

      final assembledHtml = results[0]
          .replaceFirst(
            '<!--INJECT_THEME-->',
            '<meta name="color-scheme" content="$colorScheme">\n'
                '<style>html, body { background: $cssColor; }</style>',
          )
          .replaceFirst('<!--INJECT_SDK-->', '<script>\n${results[1]}\n</script>');

      switch (UpholdPaymentWidget.htmlLoaderOverride) {
        case final loader?:
          await loader(_controller, assembledHtml);
        case _:
          _tempDir?.delete(recursive: true).ignore();
          final dir = _tempDir = await Directory.systemTemp.createTemp('uphold_payment_');
          final tempFile = File('${dir.path}/payment_widget.html');
          await tempFile.writeAsString(assembledHtml);
          await _controller.loadFile(tempFile.path);
      }
      _startTimeoutTimer();
    } catch (e) {
      _emitError(
        PaymentWidgetError(
          name: 'AssetLoadError',
          code: 'asset_load_failed',
          message: 'Could not load Payment Widget assets: $e',
        ),
      );
    }
  }

  Future<void> _injectSession() async {
    final sessionJson = jsonEncode(_activeSession.toJson());

    // Merge locale into options if provided.
    final baseOptions = widget.config.options?.toJson() ?? {};
    if (widget.config.locale case final locale?) {
      baseOptions['locale'] = locale;
    }
    final optionsJson = baseOptions.isNotEmpty ? jsonEncode(baseOptions) : 'null';

    await _controller.runJavaScript("initWidget('${_escapeJs(sessionJson)}', '${_escapeJs(optionsJson)}');");
  }

  /// Reloads the session — used by [UpholdPaymentWidgetController.reload]
  /// and the internal session-refresh flow.
  Future<void> _reloadSession() async {
    _initialized = false;
    _timeoutTimer?.cancel();

    if (mounted) {
      setState(() {
        _phase = _WidgetPhase.loading;
        _currentError = null;
      });
    }

    await _loadAssets();
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();

    if (widget.config.loadingTimeout case final timeout?) {
      _timeoutTimer = Timer(timeout, () {
        if (_phase == _WidgetPhase.loading && mounted) {
          _emitError(
            const PaymentWidgetError(
              name: 'TimeoutError',
              code: 'loading_timeout',
              message: 'Payment Widget did not become ready within the timeout period.',
            ),
          );
        }
      });
    }
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    try {
      switch (PaymentWidgetEvent.fromMessage(message.message)) {
        case PaymentWidgetReadyEvent():
          _timeoutTimer?.cancel();
          if (mounted) setState(() => _phase = _WidgetPhase.ready);
          widget.onReady?.call();

        case PaymentWidgetCompleteEvent(result: final result):
          widget.onComplete?.call(result);

        case PaymentWidgetCancelEvent():
          widget.onCancel?.call();

        case PaymentWidgetErrorEvent(error: final error):
          _handleError(error);
      }
    } catch (e) {
      debugPrint('[UpholdPaymentWidget] Bridge parse error: $e');
    }
  }

  void _handleError(PaymentWidgetError error) {
    if (error.code == 'entity_not_found' && widget.sessionProvider != null) {
      _refreshSession();
      return;
    }

    _emitError(error);
  }

  void _emitError(PaymentWidgetError error) {
    if (mounted) {
      setState(() {
        _phase = _WidgetPhase.error;
        _currentError = error;
      });
    }
    widget.onError?.call(error);
  }

  Future<void> _refreshSession() async {
    try {
      if (mounted) {
        setState(() {
          _phase = _WidgetPhase.loading;
          _currentError = null;
        });
      }

      _activeSession = await widget.sessionProvider!();
      await _reloadSession();
    } catch (e) {
      _emitError(
        PaymentWidgetError(
          name: 'SessionRefreshError',
          code: 'session_refresh_failed',
          message: 'Failed to refresh session: $e',
        ),
      );
    }
  }

  /// Converts a Flutter [Color] to a CSS rgba() string.
  static String _colorToCss(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final a = color.a;
    return 'rgba($r, $g, $b, $a)';
  }

  static bool _isDark(Color color) => color.computeLuminance() < 0.5;

  static String _escapeJs(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n').replaceAll('\r', '\\r');

  @override
  Widget build(BuildContext context) => switch (_phase) {
    _WidgetPhase.error => switch ((_currentError, widget.errorBuilder)) {
      (final error?, final errorBuilder?) => errorBuilder(context, error),
      _ => WebViewWidget(controller: _controller),
    },
    _WidgetPhase.loading => Stack(
      children: [
        WebViewWidget(controller: _controller),
        widget.loadingBuilder?.call(context) ?? const Center(child: CircularProgressIndicator.adaptive()),
      ],
    ),
    _WidgetPhase.ready => WebViewWidget(controller: _controller),
  };
}
