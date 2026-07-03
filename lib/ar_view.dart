import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'theme.dart';

// ===========================================================================
// Standalone "Heritage in 3D / AR" feature — a preview / coming-soon screen
// with one working demo so users can see how the 3D & AR viewer works.
// ===========================================================================
class ArIntroPage extends StatelessWidget {
  const ArIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Heritage in 3D / AR')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          // Hero icon
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.view_in_ar,
                  size: 64, color: colors.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Explore heritage in 3D & AR',
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.s),
          // "Coming soon" pill
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.m, vertical: 6),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'Coming soon',
                style: text.labelMedium
                    ?.copyWith(color: colors.onTertiaryContainer),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          Text(
            'Soon you\'ll be able to view Mandaluyong\'s heritage churches as '
            '3D models and place them life-size in the real world using your '
            'camera. Here\'s a quick demo of how it will work.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.outline, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ArViewPage(title: '3D / AR demo'),
              ),
            ),
            icon: const Icon(Icons.view_in_ar_outlined),
            label: const Text('Try the 3D / AR demo'),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'The demo uses a sample model to show the 3D viewer and the '
            '“View in AR” button.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: colors.outline),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 3D / AR viewer.
// Shows an interactive 3D model of a church. On AR-capable phones (your Note
// 10+ qualifies), the model-viewer "AR" button launches Google Scene Viewer
// to place the model life-size in the real world.
//
// Each church's model is expected at assets/models/<name>.glb. If that file
// hasn't been added yet, this page shows a sample model so AR can still be
// tested, with a note explaining how to add the real one.
// ===========================================================================
class ArViewPage extends StatefulWidget {
  const ArViewPage({super.key, required this.title, this.modelAsset});

  final String title;
  final String? modelAsset; // expected asset path; may not exist yet

  @override
  State<ArViewPage> createState() => _ArViewPageState();
}

class _ArViewPageState extends State<ArViewPage> {
  // Bundled sample church model, shown until a real per-church model is added.
  static const String _sampleModel = 'assets/models/demo_church.glb';

  late final Future<String?> _resolved; // real asset path if present, else null

  @override
  void initState() {
    super.initState();
    _resolved = _resolveModel();
  }

  /// Returns the asset path if the .glb is actually bundled, otherwise null.
  Future<String?> _resolveModel() async {
    final path = widget.modelAsset;
    if (path == null) return null;
    try {
      await rootBundle.load(path);
      return path;
    } catch (_) {
      return null; // file not added yet
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<String?>(
        future: _resolved,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final assetPath = snapshot.data; // null => use sample
          final usingSample = assetPath == null;
          final src = assetPath ?? _sampleModel;

          return Column(
            children: [
              if (usingSample) _SampleBanner(expected: widget.modelAsset),
              Expanded(
                child: ModelViewer(
                  src: src,
                  alt: '3D model of ${widget.title}',
                  ar: true,
                  arModes: const ['scene-viewer', 'webxr', 'quick-look'],
                  autoRotate: true,
                  cameraControls: true,
                  disableZoom: false,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SampleBanner extends StatelessWidget {
  const _SampleBanner({this.expected});
  final String? expected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Demo mode (no specific model requested) vs. a church whose .glb is missing.
    final message = expected == null
        ? 'Demo: a sample 3D church model showing how the viewer and the '
            '“View in AR” button work.'
        : 'Showing a sample model. Add ${expected!.split('/').last} to '
            'assets/models/ to show this church in 3D / AR.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.m),
      color: colors.tertiaryContainer,
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.onTertiaryContainer),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
