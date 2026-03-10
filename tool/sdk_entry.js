import { PaymentWidget } from '@uphold/enterprise-payment-widget-web-sdk';

// Expose the SDK class on the global scope so the HTML template can use it.
window.PaymentWidget = PaymentWidget;
