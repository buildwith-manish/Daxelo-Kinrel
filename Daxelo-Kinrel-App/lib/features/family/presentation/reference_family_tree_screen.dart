import 'package:kinrel/core/widgets/global_error_widget.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:kinrel/presentation/screens/family_tree/family_tree_painter.dart';
import 'package:kinrel/presentation/screens/family_tree/family_tree_model.dart';

class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({super.key});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _lineController;
  late AnimationController _orbitController;
  bool _focusMode = false;

  final TransformationController _transformController =
      TransformationController();

  // ── Member data (replace photoUrl with real URLs from your backend) ──
  late List<FamilyMember> _members;

  static const List<FamilyConnection> _connections = [
    FamilyConnection(fromId: 'gf1',  toId: 'f'),
    FamilyConnection(fromId: 'gm1',  toId: 'f'),
    FamilyConnection(fromId: 'gm1',  toId: 'm'),
    FamilyConnection(fromId: 'f',    toId: 'self'),
    FamilyConnection(fromId: 'm',    toId: 'self'),
    FamilyConnection(fromId: 'self', toId: 'a'),
    FamilyConnection(fromId: 'self', toId: 'u'),
    FamilyConnection(fromId: 'a',    toId: 'gf2'),
    FamilyConnection(fromId: 'a',    toId: 'c1'),
    FamilyConnection(fromId: 'u',    toId: 'gm2'),
    FamilyConnection(fromId: 'u',    toId: 'c2'),
  ];

  @override
  void initState() {
    super.initState();

    _members = [
      FamilyMember(id: 'gf1',  name: 'Ramesh Sharma',  role: 'Grandfather', nickname: 'Dadaji',  position: const Offset(160, 120),  nodeScale: 1.12),
      FamilyMember(id: 'gm1',  name: 'Sunita Sharma',  role: 'Grandmother', nickname: 'Dadiji',  position: const Offset(420, 120),  nodeScale: 1.12),
      FamilyMember(id: 'f',    name: 'Vikram Sharma',  role: 'Father',      nickname: 'Pitaji',  position: const Offset(220, 285)),
      FamilyMember(id: 'm',    name: 'Priya Sharma',   role: 'Mother',      nickname: 'Mataji',  position: const Offset(375, 285)),
      FamilyMember(id: 'a',    name: 'Anjali Gopta',   role: 'Aunt',        nickname: 'Masi',    position: const Offset(100, 450)),
      FamilyMember(id: 'self', name: 'Aarav Sharma',   role: 'Self',        nickname: 'You',     position: const Offset(295, 450),  isSelf: true),
      FamilyMember(id: 'u',    name: 'Suresh Gupta',   role: 'Uncle',       nickname: 'Mausa',   position: const Offset(488, 450)),
      FamilyMember(id: 'c1',   name: 'Dili Gupta',     role: 'Cousin',      nickname: 'Didi',    position: const Offset(58,  615)),
      FamilyMember(id: 'gf2',  name: 'Ramsh Sharma',   role: 'Grandfather', nickname: 'Dadaji',  position: const Offset(210, 615),  nodeScale: 1.12),
      FamilyMember(id: 'gm2',  name: 'Sunite Sharma',  role: 'Grandmother', nickname: 'Dadiji',  position: const Offset(375, 615),  nodeScale: 1.12),
      FamilyMember(id: 'c2',   name: 'Annah G',        role: 'Cousin',      nickname: 'Me',      position: const Offset(515, 615)),
    ];

    _pulseController = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

    _lineController = AnimationController(
      vsync: this, duration: const Duration(seconds: 3))..repeat();

    _orbitController = AnimationController(
      vsync: this, duration: const Duration(seconds: 12))..repeat();

    _loadImages();
  }

  /// Load each member's photoUrl as a ui.Image so the painter can render it.
  Future<void> _loadImages() async {
    for (final member in _members) {
      if (member.photoUrl == null) continue;
      try {
        final response = await http.get(Uri.parse(member.photoUrl!));
        if (response.statusCode == 200) {
          final codec = await ui.instantiateImageCodec(
              Uint8List.fromList(response.bodyBytes));
          final frame = await codec.getNextFrame();
          member.loadedImage = frame.image;
        }
      } catch (_) {
        // Falls back to silhouette placeholder silently
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _lineController.dispose();
    _orbitController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        children: [
          // ── World map background ─────────────────────────────────
          Positioned.fill(
            child: Opacity(
              opacity: 0.09,
              child: Image.network(
                'https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/'
                'World_map_-_low_resolution.svg/1280px-World_map_-_low_resolution.svg.png',
                fit: BoxFit.cover,
                color: const Color(0xFF4FC3F7),
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),

          // ── Interactive graph canvas ─────────────────────────────
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.4,
              maxScale: 3.5,
              boundaryMargin: const EdgeInsets.all(300),
              child: Center(
                child: KinrelAnimatedBuilder(
                  animation: Listenable.merge(
                      [_pulseController, _lineController, _orbitController]),
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(580, 760),
                      painter: FamilyTreePainter(
                        members: _members,
                        connections: _connections,
                        pulseValue:    _pulseController.value,
                        lineProgress:  _lineController.value,
                        orbitProgress: _orbitController.value,
                        focusMode:     _focusMode,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // ── Top app bar ──────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.arrow_back_ios,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Daxelo Kinrel Family Tree',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  // Focus Mode toggle
                  GestureDetector(
                    onTap: () => setState(() => _focusMode = !_focusMode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _focusMode
                            ? const Color(0xFF4FC3F7).withOpacity(0.15)
                            : Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _focusMode
                              ? const Color(0xFF4FC3F7).withOpacity(0.5)
                              : Colors.white.withOpacity(0.18),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _focusMode
                                ? Icons.visibility
                                : Icons.visibility_off_outlined,
                            color: _focusMode
                                ? const Color(0xFF4FC3F7)
                                : Colors.white60,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Focus Mode',
                            style: TextStyle(
                              color: _focusMode
                                  ? const Color(0xFF4FC3F7)
                                  : Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.person_outline,
                      color: Colors.white60, size: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
