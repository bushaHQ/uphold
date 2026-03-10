# uphold

Flutter package that wraps the [Uphold Payment Widget SDK](https://developer.uphold.com/widgets/payment/introduction) in a WebView with a type-safe Dart event bridge.

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Your Flutter App                                │
│  ┌────────────────────────────────────────────┐  │
│  │  UpholdPaymentWidget (StatefulWidget)      │  │
│  │  ┌──────────────────────────────────────┐  │  │
│  │  │  WebView                             │  │  │
│  │  │  ┌────────────────────────────────┐  │  │  │
│  │  │  │  payment_widget.html           │  │  │  │
│  │  │  │  + inlined payment_widget_sdk  │  │  │  │
│  │  │  │  ┌──────────────────────────┐  │  │  │  │
│  │  │  │  │  Uphold iframe           │  │  │  │  │
│  │  │  │  └──────────────────────────┘  │  │  │  │
│  │  │  └────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────┘  │  │
│  └─────────────────────┬──────────────────────┘  │
│                        │ JavaScriptChannel        │
│            ┌───────────┴───────────┐              │
│            │  PaymentWidgetBridge  │              │
│            └───────────┬───────────┘              │
│  onReady / onComplete / onCancel / onError        │
└──────────────────────────────────────────────────┘
```

The HTML template and the bundled JS SDK are both shipped as **package assets**.
At runtime the widget inlines the SDK into the HTML and loads it via
`loadHtmlString` — zero network requests are needed to bootstrap the widget.

## Setup

### 1. Bundle the JS SDK (one-time)

The Uphold SDK is an npm package that must be compiled into a single JS file.
A build script is included:

```bash
# Requires Node.js ≥ 18
cd path/to/uphold_payment_widget
./tool/build_sdk.sh        # production (minified)
./tool/build_sdk.sh --dev  # development
```

This runs `npm install` + `esbuild` and outputs `assets/payment_widget_sdk.js`.

> **Note**: `payment_widget_sdk.js` is **not** committed to the repo — it is
> built automatically by the release CI and included in the release artifact.

### 2. Add the dependency

Install from a specific release tag:

```yaml
dependencies:
  uphold_payment_widget:
    git:
      url: https://github.com/bushaHQ/uphold
      ref: v0.1.0  # replace with the desired release tag
```

### 3. Create sessions server-side

Your backend calls Uphold's Create Session endpoint with your enterprise
credentials and returns the session JSON to the app. **Never ship Uphold API
keys in client code.**

```
POST /v0/widgets/payment/sessions
→ { url, token, flow }
```

Docs: https://developer.uphold.com/rest-apis/widgets-api/payment/create-session

## Usage

```dart
import 'package:uphold_payment_widget/uphold_payment_widget.dart';

UpholdPaymentWidget(
  config: UpholdPaymentWidgetConfig(
    session: session,     // As gotten from your backend
    options: PaymentWidgetOptions(
      debug: true,
      paymentMethods: [
        CardPaymentMethod(),
        BankPaymentMethod(),
        CryptoPaymentMethod(
          assets: PaymentAssetFilter.include(['BTC', 'ETH', 'XRP']),
        ),
      ],
    ),
  ),
  onReady:    () => print('Ready'),
  onComplete: (result) => handleResult(result),
  onCancel:   () => Navigator.pop(context),
  onError:    (error) => print('${error.code}: ${error.message}'),
)
```

### Handling results

Results are a sealed class, so you get exhaustive switches:

```dart
switch (result) {
  case ExternalAccountResult(:final selection):
    // Saved card or bank account.

  case DepositMethodResult(:final depositMethod, :final account):
    // Bank transfer instructions or crypto deposit address.

  case CryptoNetworkResult(:final network, :final address, :final reference):
    // Crypto withdrawal address + optional tag/memo.
  
  case AuthorizeResult(:final transaction, :final triggerReason):
    // 3DS card auth result — check transaction['status'].

  case UnknownResult(:final raw):
    // Future-proof fallback.
}
```

## Package structure

```
uphold_payment_widget/
├── assets/
│   ├── payment_widget.html          # HTML template (ships with package)
│   └── payment_widget_sdk.js        # Bundled JS SDK (generated)
├── lib/
│   ├── uphold_payment_widget.dart   # barrel export
│   └── src/
│       ├── models.dart              # session, options, events, results
│       └── uphold_payment_widget.dart
├── tool/
│   ├── build_sdk.sh                 # SDK bundling script
│   └── sdk_entry.js                 # esbuild entry point
├── example/
│   └── lib/main.dart                # full working example
├── package.json                     # npm deps for SDK bundling
└── pubspec.yaml
```

## Notes

- Minimum widget size: **400 × 600 px**.
- The `authorize` flow handles 3DS card auth — the WebView navigation delegate
  allows external redirects for challenge pages.
- `PaymentWidgetError` implements `Exception`, so it can be thrown/caught
  naturally in Dart.
- Asset codes are uppercase: `'BTC'`, `'ETH'`, `'XRP'`, `'GBP'`, etc.
