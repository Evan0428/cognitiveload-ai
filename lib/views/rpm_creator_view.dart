import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/rpm_service.dart';
import '../theme/app_theme.dart';

/// Ready Player Me 3D avatar builder, embedded in a WebView.
///
/// Uses the free public `demo.readyplayer.me` subdomain (no account needed).
/// To brand it later, create a free subdomain at studio.readyplayer.me and
/// change [_rpmUrl]. On "avatar exported" RPM posts the `.glb` URL, which we
/// capture via a JS channel and save.
class RpmCreatorView extends StatefulWidget {
  final bool onboarding;
  const RpmCreatorView({super.key, this.onboarding = false});

  @override
  State<RpmCreatorView> createState() => _RpmCreatorViewState();
}

class _RpmCreatorViewState extends State<RpmCreatorView> {
  final RpmService _service = RpmService();
  late final WebViewController _controller;
  bool _loading = true;
  bool _saved = false;

  static const _rpmUrl = 'https://demo.readyplayer.me/avatar?frameApi';

  // Subscribes to RPM frame events and forwards the exported avatar URL.
  static const _bridgeJs = '''
    (function(){
      function receive(event){
        var data = event.data;
        try { if (typeof data === 'string') data = JSON.parse(data); } catch(e){ return; }
        if (!data || data.source !== 'readyplayerme') return;
        if (data.eventName === 'v1.frame.ready') {
          window.postMessage(JSON.stringify({
            target: 'readyplayerme', type: 'subscribe', eventName: 'v1.**'
          }), '*');
        }
        if (data.eventName === 'v1.avatar.exported') {
          FlutterRPM.postMessage(data.data.url);
        }
      }
      window.addEventListener('message', receive);
      document.addEventListener('message', receive);
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.background)
      ..addJavaScriptChannel('FlutterRPM',
          onMessageReceived: (m) => _onAvatarExported(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _controller.runJavaScript(_bridgeJs);
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(_rpmUrl));
  }

  Future<void> _onAvatarExported(String url) async {
    if (_saved || !url.endsWith('.glb')) return;
    _saved = true;
    await _service.save(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Your 3D avatar is ready!'),
          backgroundColor: AppTheme.success),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.onboarding,
        title: Text(widget.onboarding ? 'Create Your 3D Avatar' : 'My 3D Avatar'),
        actions: [
          if (widget.onboarding)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip for now',
                  style: TextStyle(color: AppTheme.inkSoft)),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.indigo),
                  SizedBox(height: 12),
                  Text('Loading avatar builder…',
                      style: TextStyle(color: AppTheme.inkSoft)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
