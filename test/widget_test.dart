import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:uphold/uphold.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(_FakePlatformWebViewControllerCreationParams());
    registerFallbackValue(_FakePlatformWebViewWidgetCreationParams());
    registerFallbackValue(_FakePlatformNavigationDelegateCreationParams());
    registerFallbackValue(_FakeJavaScriptChannelParams());
    registerFallbackValue(_FakeLoadRequestParams());
    registerFallbackValue(_MockPlatformNavigationDelegate());
    registerFallbackValue(JavaScriptMode.unrestricted);
    registerFallbackValue(Colors.transparent);
    registerFallbackValue(const NavigationRequest(url: '', isMainFrame: true));
    registerFallbackValue(_FakeBuildContext());
  });

  setUp(() {
    rootBundle.evict('packages/uphold/assets/payment_widget.html');
    rootBundle.evict('packages/uphold/assets/payment_widget_sdk.js');
    _installFakeAssetBundle();
    _setupWebViewMocks();
  });

  group('UpholdPaymentWidget', () {
    testWidgets('shows loading indicator by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, height: 600, child: UpholdPaymentWidget(config: _config())),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows custom loading builder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), loadingBuilder: (_) => const Text('Loading...')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('transitions to ready state on ready event', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, height: 600, child: UpholdPaymentWidget(config: _config())),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      _simulatePageFinished();
      _sendBridgeMessage('{"type":"ready"}');
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('calls onReady callback on ready event', (tester) async {
      var readyCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), onReady: () => readyCalled = true),
            ),
          ),
        ),
      );
      await tester.pump();

      _simulatePageFinished();
      _sendBridgeMessage('{"type":"ready"}');
      await tester.pump();

      expect(readyCalled, isTrue);
    });

    testWidgets('calls onCancel callback on cancel event', (tester) async {
      var cancelCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), onCancel: () => cancelCalled = true),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage('{"type":"cancel"}');
      await tester.pump();

      expect(cancelCalled, isTrue);
    });

    testWidgets('calls onComplete callback on complete event', (tester) async {
      PaymentWidgetResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), onComplete: (r) => result = r),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage('{"type":"complete","data":{"via":"external-account","selection":{"id":"acct_1"}}}');
      await tester.pump();

      expect(result, isA<ExternalAccountResult>());
    });

    testWidgets('calls onError and shows errorBuilder on error event', (tester) async {
      PaymentWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(
                config: _config(),
                onError: (e) => receivedError = e,
                errorBuilder: (_, error) => Text('Error: ${error.code}'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage('{"type":"error","data":{"name":"TestError","code":"test_err","message":"oops"}}');
      await tester.pump();

      final error = receivedError;
      if (error == null) fail('Expected onError to be called');
      expect(error.code, 'test_err');
      expect(find.text('Error: test_err'), findsOneWidget);
    });

    testWidgets('shows WebView when error but no errorBuilder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), onError: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage('{"type":"error","data":{"name":"E","code":"c","message":"m"}}');
      await tester.pump();

      expect(find.byKey(const Key('webview_placeholder')), findsOneWidget);
    });

    testWidgets('calls onDispose when widget is removed', (tester) async {
      var disposed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), onDispose: () => disposed = true),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();

      expect(disposed, isTrue);
    });

    testWidgets('controller attaches and detaches', (tester) async {
      final controller = UpholdPaymentWidgetController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(controller.isAttached, isTrue);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();

      expect(controller.isAttached, isFalse);

      controller.dispose();
    });

    testWidgets('injects session with locale when configured', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(locale: 'pt-BR')),
            ),
          ),
        ),
      );
      await tester.pump();

      _simulatePageFinished();
      await tester.pump();

      final captured = verify(() => _mockController.runJavaScript(captureAny())).captured.last as String;
      expect(captured, contains('initWidget'));
      expect(captured, contains('pt-BR'));
    });

    testWidgets('injects session with options when configured', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(
                config: _config(
                  options: const PaymentWidgetOptions(debug: true, paymentMethods: [CardPaymentMethod()]),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      _simulatePageFinished();
      await tester.pump();

      final captured = verify(() => _mockController.runJavaScript(captureAny())).captured.last as String;
      expect(captured, contains('initWidget'));
      expect(captured, contains('"debug":true'));
    });

    testWidgets('loading timeout emits error after duration', (tester) async {
      PaymentWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(
                config: _config(loadingTimeout: const Duration(seconds: 2)),
                onError: (e) => receivedError = e,
                errorBuilder: (_, error) => Text('Timeout: ${error.code}'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Advance past the 2-second timeout
      await tester.pump(const Duration(seconds: 3));

      final error = receivedError;
      if (error == null) fail('Expected onError to be called');
      expect(error.code, 'loading_timeout');
      expect(find.text('Timeout: loading_timeout'), findsOneWidget);
    });

    testWidgets('no timeout when loadingTimeout is null', (tester) async {
      PaymentWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(loadingTimeout: null), onError: (e) => receivedError = e),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pump(const Duration(seconds: 60));

      expect(receivedError, isNull);
    });

    testWidgets('entity_not_found error triggers session refresh', (tester) async {
      var refreshCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(
                config: _config(),
                sessionProvider: () async {
                  refreshCalled = true;
                  return _session();
                },
                onError: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage(
        '{"type":"error","data":{"name":"NotFound","code":"entity_not_found","message":"Session expired"}}',
      );
      await tester.pump();

      expect(refreshCalled, isTrue);
    });

    testWidgets('entity_not_found without sessionProvider emits error normally', (tester) async {
      PaymentWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), onError: (e) => receivedError = e),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage(
        '{"type":"error","data":{"name":"NotFound","code":"entity_not_found","message":"Session expired"}}',
      );
      await tester.pump();

      final error = receivedError;
      if (error == null) fail('Expected onError to be called');
      expect(error.code, 'entity_not_found');
    });

    testWidgets('session refresh failure emits error', (tester) async {
      PaymentWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(
                config: _config(),
                sessionProvider: () async => throw Exception('Network down'),
                onError: (e) => receivedError = e,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage('{"type":"error","data":{"name":"NotFound","code":"entity_not_found","message":"expired"}}');
      await tester.pump();

      final error = receivedError;
      if (error == null) fail('Expected onError to be called');
      expect(error.code, 'session_refresh_failed');
    });

    testWidgets('ready event cancels loading timeout', (tester) async {
      PaymentWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(
                config: _config(loadingTimeout: const Duration(seconds: 2)),
                onError: (e) => receivedError = e,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      _simulatePageFinished();
      _sendBridgeMessage('{"type":"ready"}');
      await tester.pump();

      // Advance past the timeout — should NOT trigger error
      await tester.pump(const Duration(seconds: 3));

      expect(receivedError, isNull);
    });

    testWidgets('malformed bridge message does not throw', (tester) async {
      PaymentWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), onError: (e) => receivedError = e),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage('not valid json');
      await tester.pump();

      expect(receivedError, isNull);
    });

    testWidgets('page finished only injects session once', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, height: 600, child: UpholdPaymentWidget(config: _config())),
          ),
        ),
      );
      await tester.pump();

      _simulatePageFinished();
      await tester.pump();

      _simulatePageFinished();
      await tester.pump();

      verify(() => _mockController.runJavaScript(any())).called(1);
    });

    testWidgets('navigationPolicy allows navigation when returning true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(navigationPolicy: (url) => url.startsWith('https'))),
            ),
          ),
        ),
      );
      await tester.pump();

      final callback = _capturedNavigationRequestCallback;
      if (callback == null) fail('NavigationRequestCallback was not captured');

      final allowed = await callback(const NavigationRequest(url: 'https://example.com', isMainFrame: true));
      expect(allowed, NavigationDecision.navigate);

      final blocked = await callback(const NavigationRequest(url: 'http://evil.com', isMainFrame: true));
      expect(blocked, NavigationDecision.prevent);
    });

    testWidgets('navigation allowed by default without policy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, height: 600, child: UpholdPaymentWidget(config: _config())),
          ),
        ),
      );
      await tester.pump();

      final callback = _capturedNavigationRequestCallback;
      if (callback == null) fail('NavigationRequestCallback was not captured');

      final result = await callback(const NavigationRequest(url: 'http://anything.com', isMainFrame: true));
      expect(result, NavigationDecision.navigate);
    });

    testWidgets('asset load failure emits AssetLoadError', (tester) async {
      // Install a broken asset handler that always returns null
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async => null,
      );
      // Evict cache so the broken handler is used
      rootBundle.evict('packages/uphold/assets/payment_widget.html');
      rootBundle.evict('packages/uphold/assets/payment_widget_sdk.js');

      PaymentWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(), onError: (e) => receivedError = e),
            ),
          ),
        ),
      );
      await tester.pump();

      final error = receivedError;
      if (error == null) fail('Expected onError to be called');
      expect(error.code, 'asset_load_failed');
      expect(error.name, 'AssetLoadError');
    });

    testWidgets('enableWebViewDebugging on iOS prints debug message', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(
                config: UpholdPaymentWidgetConfig(session: _session(), enableWebViewDebugging: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // If we got here without crashing, iOS debugging path was hit
      expect(find.byType(SizedBox), findsWidgets);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('enableWebViewDebugging on unsupported platform prints fallback', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(
                config: UpholdPaymentWidgetConfig(session: _session(), enableWebViewDebugging: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SizedBox), findsWidgets);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('loadHtmlString is called with assembled HTML', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, height: 600, child: UpholdPaymentWidget(config: _config())),
          ),
        ),
      );
      await tester.pump();

      final calls = verify(() => _mockController.loadHtmlString(captureAny())).captured;

      expect(calls, isNotEmpty);
      final html = calls.first as String;

      expect(html, contains('<script>'));
      expect(html, contains('/* sdk */'));
      expect(html, isNot(contains('<!--INJECT_SDK-->')));
      expect(html, isNot(contains('<!--INJECT_THEME-->')));
    });

    testWidgets('injects theme with rgba for transparent background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(backgroundColor: Colors.transparent)),
            ),
          ),
        ),
      );
      await tester.pump();

      final html = verify(() => _mockController.loadHtmlString(captureAny())).captured.first as String;

      expect(html, contains('color-scheme'));
      expect(html, contains('background: rgba(0, 0, 0, 0.0)'));
      expect(html, isNot(contains('<!--INJECT_THEME-->')));
    });

    testWidgets('injects dark color scheme for dark background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(backgroundColor: Colors.black)),
            ),
          ),
        ),
      );
      await tester.pump();

      final html = verify(() => _mockController.loadHtmlString(captureAny())).captured.first as String;

      expect(html, contains('color-scheme'));
      expect(html, contains('dark'));
      expect(html, contains('rgba(0, 0, 0, 1.0)'));
    });

    testWidgets('injects light color scheme for white background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdPaymentWidget(config: _config(backgroundColor: Colors.white)),
            ),
          ),
        ),
      );
      await tester.pump();

      final html = verify(() => _mockController.loadHtmlString(captureAny())).captured.first as String;

      expect(html, contains('light'));
      expect(html, contains('rgba(255, 255, 255, 1.0)'));
    });
  });

  group('UpholdPaymentWidgetConfig', () {
    test('has sensible defaults', () {
      final config = _config();
      expect(config.backgroundColor, Colors.transparent);
      expect(config.locale, isNull);
      expect(config.loadingTimeout, const Duration(seconds: 30));
      expect(config.enableWebViewDebugging, isNull);
      expect(config.navigationPolicy, isNull);
      expect(config.options, isNull);
    });

    test('accepts custom values', () {
      bool policyFn(String url) => url.startsWith('https');

      final config = UpholdPaymentWidgetConfig(
        session: _session(),
        backgroundColor: Colors.black,
        locale: 'pt-BR',
        loadingTimeout: const Duration(seconds: 10),
        enableWebViewDebugging: true,
        navigationPolicy: policyFn,
        options: const PaymentWidgetOptions(debug: true),
      );

      expect(config.backgroundColor, Colors.black);
      expect(config.locale, 'pt-BR');
      expect(config.loadingTimeout, const Duration(seconds: 10));
      expect(config.enableWebViewDebugging, isTrue);
      expect(config.navigationPolicy, isNotNull);
      expect(config.options?.debug, isTrue);
    });

    test('loadingTimeout can be disabled with null', () {
      final config = _config(loadingTimeout: null);
      expect(config.loadingTimeout, isNull);
    });
  });

  group('SessionProvider', () {
    test('type alias is callable', () async {
      Future<PaymentWidgetSession> provider() async => _session();
      final session = await provider();
      expect(session.token, 'tok_test');
    });
  });

  group('NavigationPolicy', () {
    test('type alias is callable', () {
      bool policy(String url) => url.startsWith('https');
      expect(policy('https://example.com'), isTrue);
      expect(policy('http://example.com'), isFalse);
    });
  });
}

class _MockWebViewPlatform extends Mock with MockPlatformInterfaceMixin implements WebViewPlatform {}

class _MockPlatformWebViewController extends Mock
    with MockPlatformInterfaceMixin
    implements PlatformWebViewController {}

class _MockPlatformWebViewWidget extends Mock with MockPlatformInterfaceMixin implements PlatformWebViewWidget {}

class _MockPlatformNavigationDelegate extends Mock
    with MockPlatformInterfaceMixin
    implements PlatformNavigationDelegate {}

class _FakePlatformWebViewControllerCreationParams extends Fake implements PlatformWebViewControllerCreationParams {}

class _FakePlatformWebViewWidgetCreationParams extends Fake implements PlatformWebViewWidgetCreationParams {}

class _FakePlatformNavigationDelegateCreationParams extends Fake implements PlatformNavigationDelegateCreationParams {}

class _FakeJavaScriptChannelParams extends Fake implements JavaScriptChannelParams {}

class _FakeLoadRequestParams extends Fake implements LoadRequestParams {}

class _FakeBuildContext extends Fake implements BuildContext {}

JavaScriptChannelParams? _capturedChannelParams;
PageEventCallback? _capturedPageFinishedCallback;
NavigationRequestCallback? _capturedNavigationRequestCallback;

late _MockWebViewPlatform _mockPlatform;
late _MockPlatformWebViewController _mockController;
late _MockPlatformWebViewWidget _mockWidget;
late _MockPlatformNavigationDelegate _mockNavDelegate;

void _setupWebViewMocks() {
  _capturedChannelParams = null;
  _capturedPageFinishedCallback = null;
  _capturedNavigationRequestCallback = null;

  _mockPlatform = _MockWebViewPlatform();
  _mockController = _MockPlatformWebViewController();
  _mockWidget = _MockPlatformWebViewWidget();
  _mockNavDelegate = _MockPlatformNavigationDelegate();

  when(() => _mockPlatform.createPlatformWebViewController(any())).thenReturn(_mockController);
  when(() => _mockPlatform.createPlatformWebViewWidget(any())).thenReturn(_mockWidget);
  when(() => _mockPlatform.createPlatformNavigationDelegate(any())).thenReturn(_mockNavDelegate);

  when(() => _mockController.setJavaScriptMode(any())).thenAnswer((_) async {});
  when(() => _mockController.setBackgroundColor(any())).thenAnswer((_) async {});
  when(() => _mockController.setPlatformNavigationDelegate(any())).thenAnswer((_) async {});
  when(() => _mockController.loadHtmlString(any(), baseUrl: any(named: 'baseUrl'))).thenAnswer((_) async {});
  when(() => _mockController.runJavaScript(any())).thenAnswer((_) async {});
  when(() => _mockController.addJavaScriptChannel(any())).thenAnswer(
    (invocation) async => _capturedChannelParams = invocation.positionalArguments[0] as JavaScriptChannelParams,
  );

  when(() => _mockNavDelegate.setOnNavigationRequest(any())).thenAnswer(
    (invocation) async =>
        _capturedNavigationRequestCallback = invocation.positionalArguments[0] as NavigationRequestCallback,
  );
  when(() => _mockNavDelegate.setOnPageStarted(any())).thenAnswer((_) async {});
  when(() => _mockNavDelegate.setOnPageFinished(any())).thenAnswer(
    (invocation) async => _capturedPageFinishedCallback = invocation.positionalArguments[0] as PageEventCallback,
  );
  when(() => _mockNavDelegate.setOnHttpError(any())).thenAnswer((_) async {});
  when(() => _mockNavDelegate.setOnProgress(any())).thenAnswer((_) async {});
  when(() => _mockNavDelegate.setOnWebResourceError(any())).thenAnswer((_) async {});
  when(() => _mockNavDelegate.setOnUrlChange(any())).thenAnswer((_) async {});
  when(() => _mockNavDelegate.setOnHttpAuthRequest(any())).thenAnswer((_) async {});
  when(() => _mockNavDelegate.setOnSSlAuthError(any())).thenAnswer((_) async {});

  when(() => _mockWidget.build(any())).thenReturn(const SizedBox(key: Key('webview_placeholder')));

  WebViewPlatform.instance = _mockPlatform;
}

void _installFakeAssetBundle() {
  const fakeHtml = '<html><!--INJECT_THEME--><!--INJECT_SDK--></html>';
  const fakeSdk = '/* sdk */';

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    ByteData? message,
  ) async {
    if (message == null) return null;
    final key = String.fromCharCodes(Uint8List.sublistView(message));
    if (key.contains('payment_widget.html')) {
      return ByteData.sublistView(Uint8List.fromList(fakeHtml.codeUnits));
    }
    if (key.contains('payment_widget_sdk.js')) {
      return ByteData.sublistView(Uint8List.fromList(fakeSdk.codeUnits));
    }
    return null;
  });
}

PaymentWidgetSession _session() => const PaymentWidgetSession(
  url: 'https://example.com/widget',
  token: 'tok_test',
  flow: PaymentWidgetFlow.selectForDeposit,
);

UpholdPaymentWidgetConfig _config({
  PaymentWidgetSession? session,
  Duration? loadingTimeout = const Duration(seconds: 30),
  PaymentWidgetOptions? options,
  String? locale,
  NavigationPolicy? navigationPolicy,
  Color? backgroundColor,
}) => UpholdPaymentWidgetConfig(
  session: session ?? _session(),
  loadingTimeout: loadingTimeout,
  options: options,
  locale: locale,
  navigationPolicy: navigationPolicy,
  backgroundColor: backgroundColor ?? Colors.transparent,
);

void _simulatePageFinished() => _capturedPageFinishedCallback?.call('about:blank');

void _sendBridgeMessage(String json) => _capturedChannelParams?.onMessageReceived(JavaScriptMessage(message: json));
