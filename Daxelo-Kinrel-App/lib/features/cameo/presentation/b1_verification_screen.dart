// lib/features/cameo/presentation/b1_verification_screen.dart
// KINREL CAMEO — B1 GATE IN-APP VERIFICATION SCREEN (debug-only, /b1-verify route).
// Runs all 8 B1 criteria, displays results with actual values, has morph sliders,
// live Thermion viewport, portrait thumbnail, + Copy Report button.
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:thermion_flutter/thermion_flutter.dart';
import '../rendering/thermion_cameo_renderer.dart';

const _expectedMorphs = ['blink_left', 'blink_right', 'smile', 'jaw_open'];
const _glbPath = 'assets/cameo/kinrel_cameo_b1_test.glb';

class B1CriterionResult {
  const B1CriterionResult({required this.id, required this.name, required this.status, required this.value, required this.duration, this.error});
  final int id; final String name; final B1Status status; final String value; final Duration duration; final String? error;
}
enum B1Status { pass, fail, pending }

class B1VerificationScreen extends StatefulWidget {
  const B1VerificationScreen({super.key});
  @override State<B1VerificationScreen> createState() => _B1VerificationScreenState();
}

class _B1VerificationScreenState extends State<B1VerificationScreen> {
  ThermionCameoRenderer? _renderer;
  ThermionViewer? _viewer;
  final List<B1CriterionResult> _results = [];
  final Map<String, double> _morphWeights = {'blink_left': 0.0, 'blink_right': 0.0, 'smile': 0.0, 'jaw_open': 0.0};
  Uint8List? _portraitBytes;
  int _portraitWidth = 256, _portraitHeight = 256;
  bool _isRunning = false;
  String _reportText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAllCriteria());
  }

  @override
  void dispose() {
    _renderer?.dispose();
    super.dispose();
  }

  Future<void> _runAllCriteria() async {
    setState(() { _isRunning = true; _results.clear(); _reportText = ''; });
    final renderer = ThermionCameoRenderer();
    _renderer = renderer;

    // Criterion 1: Filament initializes
    final initStart = DateTime.now();
    final initResult = await renderer.initialize();
    final initDur = DateTime.now().difference(initStart);
    _addResult(B1CriterionResult(
      id: 1, name: 'Filament engine initializes',
      status: initResult.success ? B1Status.pass : B1Status.fail,
      value: initResult.success ? 'viewer created, engine=${renderer.engineName}' : 'failed: ${initResult.errorMessage}',
      duration: initDur, error: initResult.errorMessage,
    ));
    if (!initResult.success) {
      setState(() { _isRunning = false; _generateReport(); });
      return;
    }
    try { _viewer = await ThermionFlutterPlugin.createViewer(); } catch (_) {}

    // Criterion 2: Capabilities pass B1 gate
    _addResult(B1CriterionResult(
      id: 2, name: 'Capabilities pass B1 gate',
      status: initResult.capabilities.passesB1Gate ? B1Status.pass : B1Status.fail,
      value: 'passesB1Gate=${initResult.capabilities.passesB1Gate}, morph=${initResult.capabilities.morphTargets}, skeletal=${initResult.capabilities.skeletalAnimation}, pbr=${initResult.capabilities.pbrMaterials}, ibl=${initResult.capabilities.iblLighting}, shadows=${initResult.capabilities.shadows}, offscreen=${initResult.capabilities.offscreenRendering}',
      duration: Duration.zero,
    ));

    // Criterion 3: GLB loads
    final loadStart = DateTime.now();
    try {
      await renderer.loadCharacter(assetPath: _glbPath, morphTargetNames: _expectedMorphs);
      final loadDur = DateTime.now().difference(loadStart);
      _addResult(B1CriterionResult(
        id: 3, name: 'GLB loads into Filament',
        status: renderer.hasCharacter ? B1Status.pass : B1Status.fail,
        value: renderer.hasCharacter ? 'loaded $_glbPath (${loadDur.inMilliseconds}ms)' : 'hasCharacter=false',
        duration: loadDur,
      ));
    } catch (e) {
      final loadDur = DateTime.now().difference(loadStart);
      _addResult(B1CriterionResult(id: 3, name: 'GLB loads into Filament', status: B1Status.fail, value: 'threw: $e', duration: loadDur, error: e.toString()));
      setState(() { _isRunning = false; _generateReport(); });
      return;
    }

    // Criterion 4: Morph target names discovered
    final discovered = renderer.discoveredMorphTargetNames;
    final allFound = _expectedMorphs.every((n) => discovered.contains(n));
    _addResult(B1CriterionResult(
      id: 4, name: 'Morph target names discovered',
      status: allFound ? B1Status.pass : B1Status.fail,
      value: '${discovered.length} found: ${discovered.join(", ")}',
      duration: Duration.zero,
    ));

    // Criterion 5: Morph weights applied
    final morphStart = DateTime.now();
    try {
      await renderer.setMorphWeights({'smile': 0.5});
      final morphDur = DateTime.now().difference(morphStart);
      _addResult(B1CriterionResult(
        id: 5, name: 'Morph weights applied without throwing',
        status: B1Status.pass,
        value: 'setMorphWeights({"smile": 0.5}) accepted (${morphDur.inMilliseconds}ms)',
        duration: morphDur,
      ));
    } catch (e) {
      final morphDur = DateTime.now().difference(morphStart);
      _addResult(B1CriterionResult(id: 5, name: 'Morph weights applied without throwing', status: B1Status.fail, value: 'threw: $e', duration: morphDur, error: e.toString()));
    }

    // Criterion 6: renderPortrait() produces bytes
    final portraitStart = DateTime.now();
    try {
      final bytes = await renderer.renderPortrait(width: _portraitWidth, height: _portraitHeight);
      final portraitDur = DateTime.now().difference(portraitStart);
      setState(() { _portraitBytes = bytes; });
      _addResult(B1CriterionResult(
        id: 6, name: 'renderPortrait() produces non-empty bytes',
        status: bytes.isNotEmpty ? B1Status.pass : B1Status.fail,
        value: '${bytes.length} bytes (${bytes.isNotEmpty ? "non-empty" : "EMPTY"}) in ${portraitDur.inMilliseconds}ms',
        duration: portraitDur,
      ));
    } catch (e) {
      final portraitDur = DateTime.now().difference(portraitStart);
      _addResult(B1CriterionResult(id: 6, name: 'renderPortrait() produces non-empty bytes', status: B1Status.fail, value: 'threw: $e', duration: portraitDur, error: e.toString()));
    }

    // Criterion 7: Portrait is valid image
    if (_portraitBytes != null && _portraitBytes!.isNotEmpty) {
      final b = _portraitBytes!;
      final isPng = b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
      final isRgba = b.length == _portraitWidth * _portraitHeight * 4;
      _addResult(B1CriterionResult(
        id: 7, name: 'Portrait is a valid image',
        status: (isPng || isRgba) ? B1Status.pass : B1Status.fail,
        value: isPng ? 'valid PNG ($_portraitWidth x $_portraitHeight)' : isRgba ? 'raw RGBA ($_portraitWidth x $_portraitHeight)' : 'unrecognized (first bytes: ${b.sublist(0, math.min(8, b.length)).map((x) => "0x${x.toRadixString(16).padLeft(2, "0")}").join(" ")})',
        duration: Duration.zero,
      ));
    } else {
      _addResult(B1CriterionResult(id: 7, name: 'Portrait is a valid image', status: B1Status.fail, value: 'no bytes', duration: Duration.zero));
    }

    // Criterion 8: Visual deformation (manual)
    _addResult(B1CriterionResult(
      id: 8, name: 'Visual mesh deformation (manual)',
      status: B1Status.pending,
      value: 'Move sliders below. Each morph at 1.0 should visibly deform mesh; at 0.0 should return to neutral. Tap "Mark Visual PASS" when confirmed.',
      duration: Duration.zero,
    ));

    setState(() { _isRunning = false; _generateReport(); });
  }

  void _addResult(B1CriterionResult r) {
    setState(() {
      _results.removeWhere((x) => x.id == r.id);
      _results.add(r);
      _results.sort((a, b) => a.id.compareTo(b.id));
    });
  }

  Future<void> _onMorphChanged(String name, double value) async {
    setState(() { _morphWeights[name] = value; });
    if (_renderer != null && _renderer!.hasCharacter) {
      try { await _renderer!.setMorphWeights(_morphWeights); } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('setMorphWeights failed: $e')));
      }
    }
  }

  void _markVisualPass() {
    _addResult(B1CriterionResult(
      id: 8, name: 'Visual mesh deformation (manual)', status: B1Status.pass,
      value: 'User confirmed at ${DateTime.now().toIso8601String()}', duration: Duration.zero,
    ));
    _generateReport();
  }

  void _generateReport() {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════════════════════════════');
    buf.writeln('KINREL CAMEO — B1 GATE VERIFICATION REPORT');
    buf.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('Device: (fill in from adb: ro.product.model + GPU info)');
    buf.writeln('Renderer: ${_renderer?.engineName ?? "not initialized"}');
    buf.writeln('GLB: $_glbPath');
    buf.writeln('═══════════════════════════════════════════════════════════');
    buf.writeln();
    var p = 0, f = 0, pen = 0;
    for (final r in _results) {
      final s = r.status == B1Status.pass ? 'PASS' : r.status == B1Status.fail ? 'FAIL' : 'PENDING';
      buf.writeln('[$s] Criterion ${r.id}: ${r.name}');
      buf.writeln('  Value: ${r.value}');
      buf.writeln('  Duration: ${r.duration.inMilliseconds}ms');
      if (r.error != null) buf.writeln('  Error: ${r.error}');
      buf.writeln();
      if (r.status == B1Status.pass) p++; else if (r.status == B1Status.fail) f++; else pen++;
    }
    buf.writeln('═══════════════════════════════════════════════════════════');
    buf.writeln('SUMMARY: $p PASS, $f FAIL, $pen PENDING');
    buf.writeln('B1 GATE: ${f == 0 && pen == 0 && p == 8 ? "PASSED" : "NOT PASSED"}');
    buf.writeln('═══════════════════════════════════════════════════════════');
    buf.writeln();
    buf.writeln('Morph weights at report time:');
    for (final e in _morphWeights.entries) buf.writeln('  ${e.key}: ${e.value.toStringAsFixed(2)}');
    buf.writeln();
    buf.writeln('Portrait: ${_portraitBytes?.length ?? 0} bytes, ${_portraitWidth}x$_portraitHeight');
    setState(() { _reportText = buf.toString(); });
  }

  Future<void> _copyReport() async {
    if (_reportText.isEmpty) _generateReport();
    await Clipboard.setData(ClipboardData(text: _reportText));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('B1 Gate Verification'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _isRunning ? null : _runAllCriteria, tooltip: 'Re-run'),
          IconButton(icon: const Icon(Icons.copy), onPressed: _copyReport, tooltip: 'Copy report'),
        ],
      ),
      body: _isRunning && _results.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
            ..._results.map(_buildCard),
            const SizedBox(height: 24),
            if (_viewer != null) ...[
              const Text('Live Thermion Viewport', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(height: 300, decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.black), child: ThermionWidget(viewer: _viewer!)),
              const SizedBox(height: 16),
              const Text('Morph Target Weights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._morphWeights.entries.map((e) => _buildSlider(e.key, e.value)),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _markVisualPass, icon: const Icon(Icons.check), label: const Text('Mark Visual PASS (criterion 8)')),
            ] else
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)), child: const Text('Live viewport unavailable. Morph sliders + portrait capture still work.')),
            const SizedBox(height: 24),
            if (_portraitBytes != null && _portraitBytes!.isNotEmpty) ...[
              const Text('renderPortrait() Output', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildPortrait(),
            ],
            const SizedBox(height: 24),
            const Text('Full Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: SelectableText(_reportText.isEmpty ? '(run criteria)' : _reportText, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
          ]),
    );
  }

  Widget _buildCard(B1CriterionResult r) {
    final c = r.status == B1Status.pass ? Colors.green : r.status == B1Status.fail ? Colors.red : Colors.orange;
    final i = r.status == B1Status.pass ? Icons.check_circle : r.status == B1Status.fail ? Icons.error : Icons.pending;
    return Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(i, color: c, size: 24), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Criterion ${r.id}: ${r.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(r.value, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(height: 2),
        Text('${r.duration.inMilliseconds}ms', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ])),
    ])));
  }

  Widget _buildSlider(String name, double value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      SizedBox(width: 100, child: Text(name, style: const TextStyle(fontFamily: 'monospace'))),
      Expanded(child: Slider(value: value, min: 0.0, max: 1.0, divisions: 100, label: value.toStringAsFixed(2), onChanged: (v) => _onMorphChanged(name, v))),
      SizedBox(width: 50, child: Text(value.toStringAsFixed(2), style: const TextStyle(fontFamily: 'monospace', fontSize: 12), textAlign: TextAlign.end)),
    ]));
  }

  Widget _buildPortrait() {
    final b = _portraitBytes!;
    final isPng = b.length >= 8 && b[0] == 0x89 && b[1] == 0x50;
    return Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (isPng) Image.memory(b, width: 128, height: 128, gaplessPlayback: true, errorBuilder: (_, e, __) => Container(width: 128, height: 128, color: Colors.red.shade100, child: Center(child: Text('decode error: $e'))))
      else Container(width: 128, height: 128, color: Colors.blue.shade100, child: const Center(child: Text('Raw RGBA\n(not PNG)', textAlign: TextAlign.center, style: TextStyle(fontSize: 10)))),
      const SizedBox(height: 8),
      Text('Bytes: ${b.length}'),
      Text('Dimensions: $_portraitWidth x $_portraitHeight'),
      Text('Format: ${isPng ? "PNG" : "raw RGBA (or unknown)"}'),
    ]));
  }
}
