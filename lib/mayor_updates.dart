import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'theme.dart';
import 'motion.dart';

// ===========================================================================
// Mayor's Updates — the official Facebook page of the Mandaluyong City Mayor,
// embedded with Facebook's official Page Plugin so residents can scroll her
// posts (photos, videos, announcements) without leaving the app.
//
// Facebook does not allow apps to read a page's posts directly, so the
// supported way to show a live timeline is this official embed. A "Open in
// Facebook" button is always available as a fallback.
// ===========================================================================

const String kMayorName = 'Carmelita "Menchie" Aguilar-Abalos';
const String kMayorTitle = 'City Mayor of Mandaluyong';
const String kMayorFbPage = 'https://www.facebook.com/MenchieAbalosOfficial';
const String kCityHallSite = 'https://mandaluyong.gov.ph/';

/// HTML wrapper around Facebook's Page Plugin. The timeline scrolls inside
/// the plugin itself, showing recent posts with their photos.
String _facebookEmbedHtml({required int widthPx, required int heightPx}) {
  final encoded = Uri.encodeComponent(kMayorFbPage);
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    html, body { margin:0; padding:0; background:transparent; overflow-x:hidden; }
    .wrap { display:flex; justify-content:center; }
    iframe { border:none; overflow:hidden; }
  </style>
</head>
<body>
  <div class="wrap">
    <iframe
      src="https://www.facebook.com/plugins/page.php?href=$encoded&tabs=timeline&width=$widthPx&height=$heightPx&small_header=false&adapt_container_width=true&hide_cover=false&show_facepile=true&lazy=false"
      width="$widthPx" height="$heightPx"
      style="border:none;overflow:hidden"
      scrolling="no" frameborder="0" allowfullscreen="true"
      allow="autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share">
    </iframe>
  </div>
</body>
</html>
''';
}

class MayorUpdatesPage extends StatefulWidget {
  const MayorUpdatesPage({super.key});

  @override
  State<MayorUpdatesPage> createState() => _MayorUpdatesPageState();
}

class _MayorUpdatesPageState extends State<MayorUpdatesPage> {
  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    // Size the plugin to the phone's width so posts fill the screen.
    final media = MediaQuery.of(context);
    final width = (media.size.width - AppSpacing.l * 2).clamp(180, 500).toInt();
    final height = (media.size.height * 0.78).toInt();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _loading = false;
                _failed = true;
              });
            }
          },
          // Taps on a post should open the real Facebook app/browser.
          onNavigationRequest: (req) {
            if (req.isMainFrame && req.url.contains('facebook.com')) {
              _open(req.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(
        _facebookEmbedHtml(widthPx: width, heightPx: height),
        baseUrl: 'https://www.facebook.com',
      );
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mayor's Updates"),
        actions: [
          IconButton(
            tooltip: 'Open in Facebook',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _open(kMayorFbPage),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          // ---- Office of the City Mayor header ----
          Reveal(
            delayMs: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.primary, colors.primaryContainer],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        child: const Icon(Icons.account_balance_rounded,
                            color: Colors.white),
                      ),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Office of the City Mayor',
                              style: text.labelMedium?.copyWith(
                                color:
                                    colors.onPrimary.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              kMayorName,
                              style: text.titleMedium?.copyWith(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              kMayorTitle,
                              style: text.bodySmall?.copyWith(
                                color:
                                    colors.onPrimary.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _open(kMayorFbPage),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1877F2), // FB blue
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.facebook),
                          label: const Text('Facebook'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _open(kCityHallSite),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.onPrimary,
                            side: BorderSide(
                                color:
                                    colors.onPrimary.withValues(alpha: 0.6)),
                          ),
                          icon: const Icon(Icons.language),
                          label: const Text('City site'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          Reveal(
            delayMs: 80,
            child: Row(
              children: [
                const Icon(Icons.campaign_rounded, size: 20),
                const SizedBox(width: AppSpacing.s),
                Text('Latest posts', style: text.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Reveal(
            delayMs: 120,
            child: Text(
              'Straight from the Mayor\'s official Facebook page — scroll to '
              'see her latest announcements, photos and videos.',
              style: text.bodySmall?.copyWith(color: colors.outline),
            ),
          ),
          const SizedBox(height: AppSpacing.m),

          // ---- Embedded Facebook timeline ----
          Reveal(
            delayMs: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.78,
                color: colors.surfaceContainerHighest,
                child: _failed
                    ? _FallbackCard(onOpen: () => _open(kMayorFbPage))
                    : Stack(
                        children: [
                          if (_controller != null)
                            WebViewWidget(controller: _controller!),
                          if (_loading)
                            const Center(child: CircularProgressIndicator()),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          Card(
            color: colors.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.outline),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      'Posts are shown directly from Facebook. Tap any post to '
                      'open it in the Facebook app for comments and videos.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown if the embed can't load (no internet, or Facebook blocked it).
class _FallbackCard extends StatelessWidget {
  const _FallbackCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.facebook, size: 56, color: colors.outline),
            const SizedBox(height: AppSpacing.l),
            Text(
              'Couldn\'t load the feed here',
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Check your internet connection, or open the Mayor\'s page '
              'directly in Facebook.',
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.l),
            FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1877F2),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in Facebook'),
            ),
          ],
        ),
      ),
    );
  }
}
