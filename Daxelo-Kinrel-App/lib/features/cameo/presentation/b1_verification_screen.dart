// lib/features/cameo/presentation/b1_verification_screen.dart
//
// KINREL CAMEO — B1 GATE VERIFICATION / CAMEO VIEWER SCREEN
//
// This screen serves two purposes:
//   1. On native platforms (Android/iOS/macOS): runs B1 gate verification
//      with live 3D Thermion rendering, morph sliders, and diagnostics.
//   2. On web: shows a polished 2D CameoAvatar fallback with a clear
//      message that 3D is not available on this platform.
//
// NEVER shows raw stack traces, raw exceptions, or debug output to the user.
// All errors are caught and presented as friendly messages.

import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:thermion_flutter/thermion_flutter.dart';

import '../rendering/thermion_cameo_renderer.dart';
import '../rendering/cameo_renderer.dart';
import 'widgets/cameo_avatar.dart';
import '../style/cameo_shape_language.dart' show CameoAgeBand;

const _expectedMorphs = ['blink_left', 'blink_right', 'smile', 'jaw_open'];
const _glbPath = 'assets/cameo/kinrel_cameo_b1_test.glb';

class B1CriterionResult {
  const B1CriterionResult({
    required this.id,
    required this.name,
    required this.status,
    required this.value,
    required this.duration,
  });
  final int id;
  final String name;
  final B1Status status;
  final String value;
  final Duration duration;
}

enum B1Status { pass, fail, pending }

class B1VerificationScreen extends StatefulWidget {
  const B1VerificationScreen({super.key});

  @override
  State<B1VerificationScreen> createState() => _B1VerificationScreenState();
}

class _B1VerificationScreenState extends State<B1VerificationScreen> {
  ThermionCameoRenderer? _renderer;
  ThermionViewer? _viewer;
  final List<B1CriterionResult> _results = [];
  final Map<String, double> _morphWeights = {
    'blink_left': 0.0,
    'blink_right': 0.0,
    'smile': 0.0,
    'jaw_open': 0.0,
  };
  Uint8List? _portraitBytes;
  final int _portraitWidth = 256, _portraitHeight = 256;
  bool _isRunning = false;
  String _reportText = '';
  String? _friendlyError;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runAllCriteria());
    }
  }

  @override
  void dispose() {
    _renderer?.dispose();
    super.dispose();
  }

  Future<void> _runAllCriteria() async {
    setState(() {
      _isRunning = true;
      _results.clear();
      _reportText = '';
      _friendlyError = null;
    });

    final renderer = ThermionCameoRenderer();
    _renderer = renderer;

    // ── Criterion 1: Filament initializes ──
    final initStart = DateTime.now();
    late final CameoRendererInitResult initResult;
    try {
      initResult = await renderer.initialize();
    } catch (e) {
      initResult = CameoRendererInitResult(
        success: false,
        capabilities: const CameoRendererCapabilities(
          morphTargets: false, skeletalAnimation: false, pbrMaterials: false,
          iblLighting: false, shadows: false, ambientOcclusion: false,
          offscreenRendering: false, animationBlending: false,
          transparentRendering: false, textureCompression: false,
        ),
        errorMessage: '3D engine could not start on this device.',
      );
    }
    final initDur = DateTime.now().difference(initStart);

    _addResult(B1CriterionResult(
      id: 1,
      name: 'Filament engine initializes',
      status: initResult.success ? B1Status.pass : B1Status.fail,
      value: initResult.success
          ? 'Engine ready (${renderer.engineName})'
          : '3D engine unavailable on this device',
      duration: initDur,
    ));

    if (!initResult.success) {
      setState(() {
        _isRunning = false;
        _friendlyError = '3D rendering is not available on this device. '
            'The 2D Kinrel Cameo is shown instead.';
        _generateReport();
      });
      return;
    }

    try {
      _viewer = await ThermionFlutterPlugin.createViewer();
    } catch (_) {}

    // ── Criterion 2: Capabilities ──
    _addResult(B1CriterionResult(
      id: 2,
      name: 'Capabilities pass B1 gate',
      status: initResult.capabilities.passesB1Gate ? B1Status.pass : B1Status.fail,
      value: 'passesB1Gate=${initResult.capabilities.passesB1Gate}',
      duration: Duration.zero,
    ));

    // ── Criterion 3: GLB loads ──
    final loadStart = DateTime.now();
    try {
      await renderer.loadCharacter(assetPath: _glbPath, morphTargetNames: _expectedMorphs);
      final loadDur = DateTime.now().difference(loadStart);
      _addResult(B1CriterionResult(
        id: 3,
        name: 'GLB loads into Filament',
        status: renderer.hasCharacter ? B1Status.pass : B1Status.fail,
        value: renderer.hasCharacter
            ? 'Character loaded (${loadDur.inMilliseconds}ms)'
            : 'Character failed to load',
        duration: loadDur,
      ));
    } catch (e) {
      final loadDur = DateTime.now().difference(loadStart);
      _addResult(B1CriterionResult(
        id: 3,
        name: 'GLB loads into Filament',
        status: B1Status.fail,
        value: 'Character could not be loaded',
        duration: loadDur,
      ));
      setState(() {
        _isRunning = false;
        _friendlyError = 'The 3D character could not be loaded. '
            'The 2D Kinrel Cameo is shown instead.';
        _generateReport();
      });
      return;
    }

    // ── Criterion 4: Morph target names ──
    final discovered = renderer.discoveredMorphTargetNames;
    final allFound = _expectedMorphs.every((n) => discovered.contains(n));
    _addResult(B1CriterionResult(
      id: 4,
      name: 'Morph target names discovered',
      status: allFound ? B1Status.pass : B1Status.fail,
      value: '${discovered.length} found: ${discovered.join(", ")}',
      duration: Duration.zero,
    ));

    // ── Criterion 5: Morph weights applied ──
    final morphStart = DateTime.now();
    try {
      await renderer.setMorphWeights({'smile': 0.5});
      final morphDur = DateTime.now().difference(morphStart);
      _addResult(B1CriterionResult(
        id: 5,
        name: 'Morph weights applied',
        status: B1Status.pass,
        value: 'Smile morph applied (${morphDur.inMilliseconds}ms)',
        duration: morphDur,
      ));
    } catch (e) {
      final morphDur = DateTime.now().difference(morphStart);
      _addResult(B1CriterionResult(
        id: 5,
        name: 'Morph weights applied',
        status: B1Status.fail,
        value: 'Could not apply morph weights',
        duration: morphDur,
      ));
    }

    // ── Criterion 6: renderPortrait ──
    final portraitStart = DateTime.now();
    try {
      final bytes = await renderer.renderPortrait(width: _portraitWidth, height: _portraitHeight);
      final portraitDur = DateTime.now().difference(portraitStart);
      setState(() => _portraitBytes = bytes);
      _addResult(B1CriterionResult(
        id: 6,
        name: 'Portrait render produces output',
        status: bytes.isNotEmpty ? B1Status.pass : B1Status.fail,
        value: '${bytes.length} bytes (${portraitDur.inMilliseconds}ms)',
        duration: portraitDur,
      ));
    } catch (e) {
      final portraitDur = DateTime.now().difference(portraitStart);
      _addResult(B1CriterionResult(
        id: 6,
        name: 'Portrait render produces output',
        status: B1Status.fail,
        value: 'Portrait render failed',
        duration: portraitDur,
      ));
    }

    // ── Criterion 7: Portrait is valid ──
    if (_portraitBytes != null && _portraitBytes!.isNotEmpty) {
      final b = _portraitBytes!;
      final isPng = b.length >= 8 && b[0] == 0x89 && b[1] == 0x50;
      final isRgba = b.length == _portraitWidth * _portraitHeight * 4;
      _addResult(B1CriterionResult(
        id: 7,
        name: 'Portrait is a valid image',
        status: (isPng || isRgba) ? B1Status.pass : B1Status.fail,
        value: isPng ? 'Valid PNG ($_portraitWidth×$_portraitHeight)' : isRgba ? 'Raw RGBA' : 'Unknown format',
        duration: Duration.zero,
      ));
    } else {
      _addResult(B1CriterionResult(
        id: 7,
        name: 'Portrait is a valid image',
        status: B1Status.fail,
        value: 'No portrait data',
        duration: Duration.zero,
      ));
    }

    // ── Criterion 8: Visual deformation (manual) ──
    _addResult(B1CriterionResult(
      id: 8,
      name: 'Visual mesh deformation',
      status: B1Status.pending,
      value: 'Move sliders to verify. Tap "Confirm" when done.',
      duration: Duration.zero,
    ));

    setState(() {
      _isRunning = false;
      _generateReport();
    });
  }

  void _addResult(B1CriterionResult r) {
    setState(() {
      _results.removeWhere((x) => x.id == r.id);
      _results.add(r);
      _results.sort((a, b) => a.id.compareTo(b.id));
    });
  }

  Future<void> _onMorphChanged(String name, double value) async {
    setState(() => _morphWeights[name] = value);
    if (_renderer != null && _renderer!.hasCharacter) {
      try {
        await _renderer!.setMorphWeights(_morphWeights);
      } catch (_) {}
    }
  }

  void _markVisualPass() {
    _addResult(B1CriterionResult(
      id: 8,
      name: 'Visual mesh deformation',
      status: B1Status.pass,
      value: 'User confirmed',
      duration: Duration.zero,
    ));
    _generateReport();
  }

  void _generateReport() {
    final buf = StringBuffer();
    buf.writeln('KINREL CAMEO — B1 GATE VERIFICATION REPORT');
    buf.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('Platform: ${kIsWeb ? "Web" : "Native"}');
    buf.writeln('Renderer: ${_renderer?.engineName ?? "not initialized"}');
    buf.writeln('');
    var p = 0, f = 0, pen = 0;
    for (final r in _results) {
      final s = r.status == B1Status.pass ? 'PASS' : r.status == B1Status.fail ? 'FAIL' : 'PENDING';
      buf.writeln('[$s] ${r.id}: ${r.name} — ${r.value} (${r.duration.inMilliseconds}ms)');
      if (r.status == B1Status.pass) p++;
      else if (r.status == B1Status.fail) f++;
      else pen++;
    }
    buf.writeln('');
    buf.writeln('SUMMARY: $p PASS, $f FAIL, $pen PENDING');
    setState(() => _reportText = buf.toString());
  }

  Future<void> _copyReport() async {
    if (_reportText.isEmpty) _generateReport();
    await Clipboard.setData(ClipboardData(text: _reportText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── WEB FALLBACK ──
    // Thermion does not support web (WASM bindings incomplete).
    // Show a polished 2D CameoAvatar with a clear message.
    if (kIsWeb) {
      return _buildWebFallback(context);
    }

    // ── NATIVE (Android/iOS/macOS) ──
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cameo'),
        actions: [
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isRunning ? null : _runAllCriteria,
            ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyReport,
          ),
        ],
      ),
      body: _isRunning && _results.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Friendly error (if any) ──
                if (_friendlyError != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _friendlyError!,
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── 2D Fallback avatar (shown when 3D fails) ──
                if (_friendlyError != null) ...[
                  Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: CameoAvatar(
                        personName: 'User',
                        ageBand: CameoAgeBand.adult,
                        skinToneIndex: 5,
                        surfaceId: 'profile_hero',
                        isDeceased: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Criteria results ──
                ..._results.map(_buildCard),

                const SizedBox(height: 24),

                // ── Live 3D viewport + sliders (only if 3D is active) ──
                if (_viewer != null && _friendlyError == null) ...[
                  const Text('Live 3D Viewport',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          ThermionWidget(viewer: _viewer!),
                          Positioned(
                            top: 4,
                            left: 4,
                            right: 4,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'PLACEHOLDER — NOT FINAL ART',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Morph Target Sliders',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._morphWeights.entries
                      .map((e) => _buildSlider(e.key, e.value)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _markVisualPass,
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm Visual Deformation'),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Portrait thumbnail ──
                if (_portraitBytes != null && _portraitBytes!.isNotEmpty) ...[
                  const Text('Portrait Capture',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildPortrait(),
                ],
              ],
            ),
    );
  }

  /// Web fallback — polished 2D CameoAvatar with a clear message.
  Widget _buildWebFallback(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Cameo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 2D CameoAvatar — the premium fallback
              SizedBox(
                width: 200,
                height: 200,
                child: CameoAvatar(
                  personName: 'User',
                  ageBand: CameoAgeBand.adult,
                  skinToneIndex: 5,
                  surfaceId: 'profile_hero',
                  isDeceased: false,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Your Kinrel Cameo',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '3D rendering is available in the Kinrel mobile app.\n'
                'On web, your Cameo appears as a beautifully crafted 2D portrait.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(B1CriterionResult r) {
    final c = r.status == B1Status.pass
        ? Colors.green
        : r.status == B1Status.fail
            ? Colors.red
            : Colors.orange;
    final i = r.status == B1Status.pass
        ? Icons.check_circle
        : r.status == B1Status.fail
            ? Icons.error
            : Icons.pending;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(i, color: c, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r.id}: ${r.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(r.value,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(height: 2),
                  Text('${r.duration.inMilliseconds}ms',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String name, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 100,
              child: Text(name, style: const TextStyle(fontFamily: 'monospace'))),
          Expanded(
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              label: value.toStringAsFixed(2),
              onChanged: (v) => _onMorphChanged(name, v),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              value.toStringAsFixed(2),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortrait() {
    final b = _portraitBytes!;
    final isPng = b.length >= 8 && b[0] == 0x89 && b[1] == 0x50;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPng)
            Image.memory(b, width: 128, height: 128, gaplessPlayback: true)
          else
            Container(
              width: 128,
              height: 128,
              color: Colors.blue.shade100,
              child: const Center(
                child: Text('Portrait captured',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
              ),
            ),
          const SizedBox(height: 8),
          Text('Size: ${b.length} bytes'),
          Text('Dimensions: $_portraitWidth × $_portraitHeight'),
        ],
      ),
    );
  }
}
