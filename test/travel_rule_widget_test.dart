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
    rootBundle.evict('packages/uphold/assets/travel_rule_widget.html');
    rootBundle.evict('packages/uphold/assets/travel_rule_widget_sdk.js');
    _installFakeAssetBundle();
    _setupWebViewMocks();
  });

  group('UpholdTravelRuleWidget', () {
    testWidgets('shows loading indicator by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, height: 600, child: UpholdTravelRuleWidget(config: _config())),
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
              child: UpholdTravelRuleWidget(config: _config(), loadingBuilder: (_) => const Text('Loading...')),
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
            body: SizedBox(width: 400, height: 600, child: UpholdTravelRuleWidget(config: _config())),
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
              child: UpholdTravelRuleWidget(config: _config(), onReady: () => readyCalled = true),
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
              child: UpholdTravelRuleWidget(config: _config(), onCancel: () => cancelCalled = true),
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

    testWidgets('calls onComplete callback with opaque result', (tester) async {
      TravelRuleResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdTravelRuleWidget(config: _config(), onComplete: (r) => result = r),
            ),
          ),
        ),
      );
      await tester.pump();
      _simulatePageFinished();

      _sendBridgeMessage('{"type":"complete","data":{"originator":{"name":"John"},"txRef":"abc"}}');
      await tester.pump();

      expect(result, isNotNull);
      expect(result!.data['originator'], isA<Map>());
      expect(result!.data['txRef'], 'abc');
    });

    testWidgets('calls onError and shows errorBuilder on error event', (tester) async {
      TravelRuleWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdTravelRuleWidget(
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
              child: UpholdTravelRuleWidget(config: _config(), onError: (_) {}),
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
              child: UpholdTravelRuleWidget(config: _config(), onDispose: () => disposed = true),
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
      final controller = UpholdTravelRuleWidgetController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdTravelRuleWidget(config: _config(), controller: controller),
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

    testWidgets('loading timeout emits error', (tester) async {
      TravelRuleWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdTravelRuleWidget(
                config: _config(loadingTimeout: const Duration(seconds: 2)),
                onError: (e) => receivedError = e,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Advance past timeout without sending 'ready'.
      await tester.pump(const Duration(seconds: 3));

      expect(receivedError, isNotNull);
      expect(receivedError!.code, 'loading_timeout');
    });

    testWidgets('no timeout error when ready fires before timeout', (tester) async {
      TravelRuleWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdTravelRuleWidget(
                config: _config(loadingTimeout: const Duration(seconds: 5)),
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

      // Advance past timeout — should not fire.
      await tester.pump(const Duration(seconds: 6));

      expect(receivedError, isNull);
    });

    testWidgets('null loadingTimeout disables timeout', (tester) async {
      TravelRuleWidgetError? receivedError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdTravelRuleWidget(config: _config(loadingTimeout: null), onError: (e) => receivedError = e),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));

      expect(receivedError, isNull);
    });
  });

  group('Theme injection', () {
    testWidgets('injects theme markers into HTML', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, height: 600, child: UpholdTravelRuleWidget(config: _config())),
          ),
        ),
      );
      await tester.pump();

      final html = verify(() => _mockController.loadHtmlString(captureAny())).captured.first as String;

      expect(html, contains('color-scheme'));
      expect(html, isNot(contains('<!--INJECT_THEME-->')));
      expect(html, isNot(contains('<!--INJECT_SDK-->')));
    });

    testWidgets('injects dark color scheme for dark background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdTravelRuleWidget(config: _config(backgroundColor: Colors.black)),
            ),
          ),
        ),
      );
      await tester.pump();

      final html = verify(() => _mockController.loadHtmlString(captureAny())).captured.first as String;

      expect(html, contains('dark'));
    });

    testWidgets('injects light color scheme for white background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: UpholdTravelRuleWidget(config: _config(backgroundColor: Colors.white)),
            ),
          ),
        ),
      );
      await tester.pump();

      final html = verify(() => _mockController.loadHtmlString(captureAny())).captured.first as String;

      expect(html, contains('light'));
    });
  });

  group('UpholdTravelRuleWidgetConfig', () {
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

      final config = UpholdTravelRuleWidgetConfig(
        session: _session(),
        backgroundColor: Colors.black,
        locale: 'pt-BR',
        loadingTimeout: const Duration(seconds: 10),
        enableWebViewDebugging: true,
        navigationPolicy: policyFn,
        options: const TravelRuleWidgetOptions(debug: true),
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

  group('UpholdTravelRuleWidgetController', () {
    test('isAttached is false initially', () {
      final controller = UpholdTravelRuleWidgetController();
      expect(controller.isAttached, isFalse);
      controller.dispose();
    });

    test('dispose sets isAttached to false', () {
      final controller = UpholdTravelRuleWidgetController();
      controller.dispose();
      expect(controller.isAttached, isFalse);
    });

    test('reload does not throw when not attached', () async {
      final controller = UpholdTravelRuleWidgetController();
      await controller.reload();
      controller.dispose();
    });
  });
}

// ---------------------------------------------------------------------------
// Mocks & fakes (same pattern as widget_test.dart)
// ---------------------------------------------------------------------------

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

late _MockWebViewPlatform _mockPlatform;
late _MockPlatformWebViewController _mockController;
late _MockPlatformWebViewWidget _mockWidget;
late _MockPlatformNavigationDelegate _mockNavDelegate;

void _setupWebViewMocks() {
  _capturedChannelParams = null;
  _capturedPageFinishedCallback = null;

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

  when(() => _mockNavDelegate.setOnNavigationRequest(any())).thenAnswer((_) async {});
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
  const fakeSdk = '/* travel rule sdk */';

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
    ByteData? message,
  ) async {
    if (message == null) return null;
    final key = String.fromCharCodes(Uint8List.sublistView(message));
    if (key.contains('travel_rule_widget.html')) {
      return ByteData.sublistView(Uint8List.fromList(fakeHtml.codeUnits));
    }
    if (key.contains('travel_rule_widget_sdk.js')) {
      return ByteData.sublistView(Uint8List.fromList(fakeSdk.codeUnits));
    }
    // Also serve payment assets so the test runner doesn't fail
    // if those are requested during setup.
    if (key.contains('payment_widget.html')) {
      return ByteData.sublistView(Uint8List.fromList(fakeHtml.codeUnits));
    }
    if (key.contains('payment_widget_sdk.js')) {
      return ByteData.sublistView(Uint8List.fromList(fakeSdk.codeUnits));
    }
    return null;
  });
}

TravelRuleWidgetSession _session() => const TravelRuleWidgetSession(
  url: 'https://travel-rule.enterprise.uphold.com/',
  token: 'tok_test',
  flow: TravelRuleWidgetFlow.depositForm,
  data: TravelRuleWidgetData(provider: 'notabene', parameters: {'init': {}}),
);

UpholdTravelRuleWidgetConfig _config({
  TravelRuleWidgetSession? session,
  Duration? loadingTimeout = const Duration(seconds: 30),
  TravelRuleWidgetOptions? options,
  String? locale,
  TravelRuleNavigationPolicy? navigationPolicy,
  Color? backgroundColor,
}) => UpholdTravelRuleWidgetConfig(
  session: session ?? _session(),
  loadingTimeout: loadingTimeout,
  options: options,
  locale: locale,
  navigationPolicy: navigationPolicy,
  backgroundColor: backgroundColor ?? Colors.transparent,
);

void _simulatePageFinished() => _capturedPageFinishedCallback?.call('about:blank');

void _sendBridgeMessage(String json) => _capturedChannelParams?.onMessageReceived(JavaScriptMessage(message: json));
