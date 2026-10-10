import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// PayMongo's hosted checkout rendered inside the app. Watches navigation
/// for the success/cancel sentinel URLs and pops with the outcome.
class CheckoutWebViewScreen extends StatefulWidget {
  const CheckoutWebViewScreen({super.key, required this.checkoutUrl});

  final String checkoutUrl;

  @override
  State<CheckoutWebViewScreen> createState() =>
      _CheckoutWebViewScreenState();
}

class _CheckoutWebViewScreenState extends State<CheckoutWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith('https://aumazing.app/payment/success')) {
              Navigator.of(context).pop(true);
              return NavigationDecision.prevent;
            }
            if (request.url.startsWith('https://aumazing.app/payment/cancel')) {
              Navigator.of(context).pop(false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close checkout',
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
