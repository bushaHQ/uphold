# uphold

[![Test & Coverage](https://github.com/bushaHQ/uphold/actions/workflows/test.yml/badge.svg?branch=dev)](https://github.com/bushaHQ/uphold/actions/workflows/test.yml)
![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/bushaHQ/uphold/dev/coverage-badge.json)

Flutter package that wraps Uphold's enterprise widget SDKs in WebViews with type-safe Dart event bridges. Currently supports the [Payment Widget](https://developer.uphold.com/widgets/payment/introduction) and the [Travel Rule Widget](https://developer.uphold.com/widgets/travel-rule/introduction).

## Architecture

Both widgets follow the same architecture — an HTML template with the bundled JS SDK is loaded into a WebView, and events are bridged back to Dart via a JavaScriptChannel.

```
┌──────────────────────────────────────────────────┐
│  Your Flutter App                                │
│  ┌────────────────────────────────────────────┐  │
│  │  UpholdPaymentWidget / UpholdTravelRule…   │  │
│  │  ┌──────────────────────────────────────┐  │  │
│  │  │  WebView                             │  │  │
│  │  │  ┌────────────────────────────────┐  │  │  │
│  │  │  │  widget.html + inlined SDK     │  │  │  │
│  │  │  │  ┌──────────────────────────┐  │  │  │  │
│  │  │  │  │  Uphold iframe           │  │  │  │  │
│  │  │  │  └──────────────────────────┘  │  │  │  │
│  │  │  └────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────┘  │  │
│  └─────────────────────┬──────────────────────┘  │
│                        │ JavaScriptChannel        │
│            ┌───────────┴───────────┐              │
│            │  WidgetBridge         │              │
│            └───────────┬───────────┘              │
│  onReady / onComplete / onCancel / onError        │
└──────────────────────────────────────────────────┘
```

HTML templates and bundled JS SDKs are shipped as **package assets**. At runtime each widget inlines its SDK into the HTML and loads it via `loadHtmlString` — zero network requests needed to bootstrap.

## Setup

### 1. Bundle the JS SDKs (one-time)

Both Uphold SDKs are npm packages that must be compiled into single JS files. A build script is included:

```bash
# Requires Node.js ≥ 18
cd path/to/uphold
./tool/build_sdk.sh        # production (minified)
./tool/build_sdk.sh --dev  # development
```

This runs `npm install` + `esbuild` and outputs:
- `assets/payment_widget_sdk.js`
- `assets/travel_rule_widget_sdk.js`

> **Note**: These files are **not** committed to the repo — they are built automatically by the release CI and included in the release artifact.

### 2. Add the dependency

Install from a specific release tag:

```yaml
dependencies:
  uphold:
    git:
      url: https://github.com/bushaHQ/uphold
      ref: <version>  # replace with the latest release tag
```

### 3. Create sessions server-side

Your backend calls Uphold's Create Session endpoints with your enterprise credentials and returns the session JSON to the app. **Never ship Uphold API keys in client code.**

Payment: https://developer.uphold.com/rest-apis/widgets-api/payment/create-session

Travel Rule: https://developer.uphold.com/rest-apis/widgets-api/travel-rule/create-session

## Payment Widget

Handles deposits, withdrawals, and card authorization (3DS).

### Usage

```dart
import 'package:uphold/uphold.dart';

UpholdPaymentWidget(
  config: UpholdPaymentWidgetConfig(
    session: session,     // from your backend
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

Results are a sealed class with exhaustive switches:

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

## Travel Rule Widget

Collects originator/beneficiary information for crypto transactions to comply with FATF Travel Rule regulations. Used when a quote has a `travel-rule` requirement or a deposit transaction has a `travel-rule` RFI.

### Usage

```dart
import 'package:uphold/uphold.dart';

UpholdTravelRuleWidget(
  config: UpholdTravelRuleWidgetConfig(
    session: travelRuleSession,   // from your backend
    options: TravelRuleWidgetOptions(debug: true),
  ),
  onReady:    () => print('Ready'),
  onComplete: (result) {
    // result.data is opaque — forward to your backend as-is
    // when resolving RFIs or creating transactions.
    submitTravelRuleData(result.data);
  },
  onCancel:   () => Navigator.pop(context),
  onError:    (error) => print('${error.code}: ${error.message}'),
)
```

### Flows

| Flow | When to use |
|---|---|
| `TravelRuleWidgetFlow.depositForm` | A deposit transaction is on hold with a `travel-rule` RFI |
| `TravelRuleWidgetFlow.withdrawalForm` | A withdrawal quote has a `travel-rule` requirement |

### Handling the result

The complete event returns an opaque `TravelRuleResult`. Don't parse it — pass `result.data` directly to your backend:

```dart
onComplete: (result) async {
  await api.resolveQuoteRequirement(quoteId, result.data);
  // or
  await api.resolveTransactionRfi(transactionId, result.data);
}
```

## Package structure

```
uphold/
├── assets/
│   ├── payment_widget.html              # Payment HTML template
│   ├── payment_widget_sdk.js            # Payment JS SDK (generated)
│   ├── travel_rule_widget.html          # Travel Rule HTML template
│   └── travel_rule_widget_sdk.js        # Travel Rule JS SDK (generated)
├── lib/
│   ├── uphold.dart                      # barrel export
│   └── src/
│       ├── models.dart                  # Payment: session, options, events, results
│       ├── uphold.dart                  # Payment: widget, config, controller
│       ├── travel_rule_models.dart      # Travel Rule: session, flows, events, result
│       └── travel_rule_widget.dart      # Travel Rule: widget, config, controller
├── tool/
│   ├── build_sdk.sh                     # Builds both JS SDKs
│   ├── sdk_entry.js                     # Payment esbuild entry
│   └── travel_rule_sdk_entry.js         # Travel Rule esbuild entry
├── test/
│   ├── models_test.dart
│   ├── widget_test.dart
│   └── controller_test.dart
├── example/
│   └── lib/main.dart
├── package.json                         # npm deps for SDK bundling
└── pubspec.yaml
```

## Notes

- Minimum widget size: **400 × 600 px** for both widgets.
- `PaymentWidgetError` and `TravelRuleWidgetError` both implement `Exception`.
- Asset codes are uppercase: `'BTC'`, `'ETH'`, `'XRP'`, `'GBP'`, etc.
- The Payment `authorize` flow handles 3DS card auth — the WebView allows external redirects for challenge pages.
- Travel Rule `TravelRuleResult.data` is opaque — always forward it to your backend without modification.