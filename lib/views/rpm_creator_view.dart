import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/rpm_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_view.dart';

/// 3D avatar setup (Chua Yi Zhe).
///
/// Two paths:
///  • Pick a ready-made 3D character — always works, no account, offline-safe.
///  • Build a personalised 3D avatar in Ready Player Me — only when a free
///    subdomain is configured in [RpmService.subdomain] (RPM retired the old
///    public demo subdomain, so without one the builder URL doesn't exist).
class RpmCreatorView extends StatefulWidget {
  final bool onboarding;
  const RpmCreatorView({super.key, this.onboarding = false});

  @override
  State<RpmCreatorView> createState() => _RpmCreatorViewState();
}

class _RpmCreatorViewState extends State<RpmCreatorView> {
  final RpmService _service = RpmService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.onboarding,
        title: Text(widget.onboarding ? 'Choose Your 3D Assistant' : 'My 3D Avatar'),
        actions: [
          if (widget.onboarding)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip', style: TextStyle(color: AppTheme.inkSoft)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Live 3D preview of the current selection.
          Center(
            child: Container(
              height: 220,
              width: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppTheme.indigo.withValues(alpha: 0.16),
                  AppTheme.indigo.withValues(alpha: 0.0),
                ]),
              ),
              child: const AvatarView(size: 220, threeD: true),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Drag to spin your assistant',
                style: TextStyle(fontSize: 12, color: AppTheme.inkFaint)),
          ),
          const SizedBox(height: 24),

          const Text('Pick a 3D character',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.ink)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final c in RpmService.characters) ...[
                Expanded(
                  child: _CharacterTile(
                    emoji: c.emoji,
                    name: c.name,
                    selected: RpmService.avatarUrl.value == c.url,
                    onTap: () async {
                      await _service.save(c.url);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 28),

          const Text('Or build a 3D avatar that looks like you',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.ink)),
          const SizedBox(height: 8),
          if (RpmService.hasSubdomain)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.face_retouching_natural),
                label: const Text('Open Avatar Builder'),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const _RpmBuilderPage()),
                  );
                  if (mounted) setState(() {});
                },
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, size: 18, color: AppTheme.warning),
                    SizedBox(width: 8),
                    Text('Personalised builder not configured',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: AppTheme.ink)),
                  ]),
                  SizedBox(height: 8),
                  Text(
                    'Ready Player Me needs your own free subdomain.\n'
                    '1. Sign up free at studio.readyplayer.me\n'
                    '2. Copy your subdomain (e.g. "cognitiveload")\n'
                    '3. Paste it into RpmService.subdomain in the code\n\n'
                    'Until then, the 3D characters above work perfectly.',
                    style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.5),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (widget.onboarding)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: const Text('Start My Journey'),
                onPressed: () async {
                  // Ensure an avatar is set even if they didn't tap one.
                  if ((RpmService.avatarUrl.value ?? '').isEmpty) {
                    await _service.save(RpmService.defaultCharacterUrl);
                  }
                  if (mounted) Navigator.pop(context);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  final String emoji, name;
  final bool selected;
  final VoidCallback onTap;
  const _CharacterTile(
      {required this.emoji,
      required this.name,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.indigo.withValues(alpha: 0.08)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? AppTheme.indigo : AppTheme.line,
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 6),
            Text(name,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? AppTheme.indigo : AppTheme.ink)),
          ],
        ),
      ),
    );
  }
}

/// The Ready Player Me builder in a WebView (only reachable when a subdomain
/// is configured). Reports load failures instead of hanging on a blank page.
class _RpmBuilderPage extends StatefulWidget {
  const _RpmBuilderPage();

  @override
  State<_RpmBuilderPage> createState() => _RpmBuilderPageState();
}

class _RpmBuilderPageState extends State<_RpmBuilderPage> {
  final RpmService _service = RpmService();
  late final WebViewController _controller;
  bool _loading = true;
  bool _saved = false;
  String? _error;

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
          onMessageReceived: (m) => _onExported(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _controller.runJavaScript(_bridgeJs);
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (err) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = err.description;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(RpmService.builderUrl));
  }

  Future<void> _onExported(String url) async {
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
      appBar: AppBar(title: const Text('Avatar Builder')),
      body: Stack(
        children: [
          if (_error == null) WebViewWidget(controller: _controller),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 44, color: AppTheme.inkFaint),
                    const SizedBox(height: 12),
                    const Text("Couldn't load the avatar builder",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      'Check your internet and that RpmService.subdomain is a '
                      'valid Ready Player Me subdomain.\n\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.inkSoft, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Use a 3D character instead'),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading && _error == null)
            const Center(child: CircularProgressIndicator(color: AppTheme.indigo)),
        ],
      ),
    );
  }
}
