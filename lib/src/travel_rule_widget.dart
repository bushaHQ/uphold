import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'travel_rule_models.dart';

/// Callback that returns a fresh [TravelRuleWidgetSession].
typedef TravelRuleSessionProvider = Future<TravelRuleWidgetSession> Function();

/// Callback that decides whether a navigation request should be allowed.
typedef TravelRuleNavigationPolicy = bool Function(String url);

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Programmatic handle for an [UpholdTravelRuleWidget] instance.
class UpholdTravelRuleWidgetController extends ChangeNotifier {
  _UpholdTravelRuleWidgetState? _state;

  void _attach(_UpholdTravelRuleWidgetState state) => _state = state;
  void _detach() => _state = null;

  /// Whether the controller is currently attached to a live widget.
  bool get isAttached => _state != null;

  /// Re-injects the current session into the WebView.
  Future<void> reload() async => _state?._reloadSession();

  @override
  void dispose() {
    _state = null;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/// Configuration for the [UpholdTravelRuleWidget].
class UpholdTravelRuleWidgetConfig {
  /// Session obtained from Uphold's Travel Rule Create Session endpoint via your backend.
  final TravelRuleWidgetSession session;

  /// Optional widget options (debug mode).
  final TravelRuleWidgetOptions? options;

  /// Background color applied to the WebView before content loads.
  final Color backgroundColor;

  /// Locale string passed to the SDK (e.g. `'en-US'`, `'pt-BR'`).
  final String? locale;

  /// Maximum time to wait for the `ready` event before emitting a timeout error.
  ///
  /// Defaults to 30 seconds. Set to `null` to disable.
  final Duration? loadingTimeout;

  /// Enables WebView remote debugging.
  ///
  /// Defaults to `true` in debug mode, `false` in release.
  final bool? enableWebViewDebugging;

  /// Optional policy for navigation requests inside the WebView.
  final TravelRuleNavigationPolicy? navigationPolicy;

  const UpholdTravelRuleWidgetConfig({
    required this.session,
    this.options,
    this.backgroundColor = Colors.transparent,
    this.locale,
    this.loadingTimeout = const Duration(seconds: 30),
    this.enableWebViewDebugging,
    this.navigationPolicy,
  });
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Embeds the Uphold Travel Rule Widget inside a Flutter widget tree.
///
/// Used to collect originator/beneficiary information for crypto transactions
/// to comply with FATF Travel Rule regulations.
///
/// ```dart
/// UpholdTravelRuleWidget(
///   config: UpholdTravelRuleWidgetConfig(session: session),
///   onComplete: (result) => submitTravelRuleData(result.data),
///   onCancel: () => Navigator.pop(context),
///   onError: (err) => showError(err),
/// )
/// ```
class UpholdTravelRuleWidget extends StatefulWidget {
  /// Override for how assembled HTML is loaded into the WebView.
  ///
  /// Defaults to writing a temp file and using [WebViewController.loadFile]
  /// to work around a WKWebView bug with [WebViewController.loadHtmlString].
  @visibleForTesting
  static Future<void> Function(WebViewController controller, String html)? htmlLoaderOverride;

  final UpholdTravelRuleWidgetConfig config;

  /// Called when the widget has loaded and is interactive.
  final VoidCallback? onReady;

  /// Called when the travel rule form is completed.
  ///
  /// The [TravelRuleResult.data] is opaque — forward it to your backend as-is
  /// when resolving RFIs or creating transactions.
  final ValueChanged<TravelRuleResult>? onComplete;

  /// Called when the user dismisses the form.
  final VoidCallback? onCancel;

  /// Called on unrecoverable errors.
  final ValueChanged<TravelRuleWidgetError>? onError;

  /// Shown while the WebView + SDK are loading.
  final WidgetBuilder? loadingBuilder;

  /// Shown when the widget enters an error state.
  final Widget Function(BuildContext context, TravelRuleWidgetError error)? errorBuilder;

  /// Provides a fresh session when the current one expires.
  final TravelRuleSessionProvider? sessionProvider;

  /// Optional controller for programmatic access.
  final UpholdTravelRuleWidgetController? controller;

  /// Called when the widget is about to be disposed.
  final VoidCallback? onDispose;

  const UpholdTravelRuleWidget({
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
  State<UpholdTravelRuleWidget> createState() => _UpholdTravelRuleWidgetState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum _WidgetPhase { loading, ready, error }

class _UpholdTravelRuleWidgetState extends State<UpholdTravelRuleWidget> {
  late WebViewController _controller;
  _WidgetPhase _phase = _WidgetPhase.loading;
  TravelRuleWidgetError? _currentError;
  bool _initialized = false;
  Timer? _timeoutTimer;
  late TravelRuleWidgetSession _activeSession;
  Directory? _tempDir;

  static const _htmlAsset = 'packages/uphold/assets/travel_rule_widget.html';
  static const _sdkAsset = 'packages/uphold/assets/travel_rule_widget_sdk.js';

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
        debugPrint('[UpholdTravelRuleWidget] WebView debugging enabled (iOS)');
      default:
        debugPrint('[UpholdTravelRuleWidget] WebView debugging is not supported on this platform.');
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
      ..addJavaScriptChannel('TravelRuleWidgetBridge', onMessageReceived: _onBridgeMessage);
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

      switch (UpholdTravelRuleWidget.htmlLoaderOverride) {
        case final loader?:
          await loader(_controller, assembledHtml);
        case _:
          _tempDir?.delete(recursive: true).ignore();
          final dir = _tempDir = await Directory.systemTemp.createTemp('uphold_travel_rule_');
          final tempFile = File('${dir.path}/travel_rule_widget.html');
          await tempFile.writeAsString(assembledHtml);
          await _controller.loadFile(tempFile.path);
      }
      _startTimeoutTimer();
    } catch (e) {
      _emitError(
        TravelRuleWidgetError(
          name: 'AssetLoadError',
          code: 'asset_load_failed',
          message: 'Could not load Travel Rule Widget assets: $e',
        ),
      );
    }
  }

  Future<void> _injectSession() async {
    final sessionJson = jsonEncode(_activeSession.toJson());

    final baseOptions = widget.config.options?.toJson() ?? {};
    if (widget.config.locale case final locale?) {
      baseOptions['locale'] = locale;
    }
    final optionsJson = baseOptions.isNotEmpty ? jsonEncode(baseOptions) : 'null';

    await _controller.runJavaScript("initWidget('${_escapeJs(sessionJson)}', '${_escapeJs(optionsJson)}');");
  }

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
            const TravelRuleWidgetError(
              name: 'TimeoutError',
              code: 'loading_timeout',
              message: 'Travel Rule Widget did not become ready within the timeout period.',
            ),
          );
        }
      });
    }
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    try {
      switch (TravelRuleWidgetEvent.fromMessage(message.message)) {
        case TravelRuleWidgetReadyEvent():
          _timeoutTimer?.cancel();
          if (mounted) setState(() => _phase = _WidgetPhase.ready);
          widget.onReady?.call();

        case TravelRuleWidgetCompleteEvent(result: final result):
          widget.onComplete?.call(result);

        case TravelRuleWidgetCancelEvent():
          widget.onCancel?.call();

        case TravelRuleWidgetErrorEvent(error: final error):
          _handleError(error);
      }
    } catch (e) {
      debugPrint('[UpholdTravelRuleWidget] Bridge parse error: $e');
    }
  }

  void _handleError(TravelRuleWidgetError error) {
    if (error.code == 'entity_not_found' && widget.sessionProvider != null) {
      _refreshSession();
      return;
    }

    _emitError(error);
  }

  void _emitError(TravelRuleWidgetError error) {
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
        TravelRuleWidgetError(
          name: 'SessionRefreshError',
          code: 'session_refresh_failed',
          message: 'Failed to refresh Travel Rule session: $e',
        ),
      );
    }
  }

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
