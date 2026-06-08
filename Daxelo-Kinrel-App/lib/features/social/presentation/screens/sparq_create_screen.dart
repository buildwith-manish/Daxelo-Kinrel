import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/sparq_provider.dart';

class SparqCreateScreen extends ConsumerStatefulWidget {
  const SparqCreateScreen({super.key});

  @override
  ConsumerState<SparqCreateScreen> createState() => _SparqCreateScreenState();
}

class _SparqCreateScreenState extends ConsumerState<SparqCreateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _audience = 'PUBLIC';
  String? _text;
  String _backgroundColor = '#E8612A';
  File? _mediaFile;
  int? _duration;
  bool _isRecording = false;

  static const _bgColors = [
    '#E8612A', '#C44A18', '#F59240', '#3B82F6', '#4CAF7A',
    '#8B5CF6', '#EF4444', '#1A1A2E', '#16213E', '#0F3460',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentType {
    switch (_tabController.index) {
      case 0: return 'IMAGE';
      case 1: return 'VIDEO';
      case 2: return 'TEXT';
      case 3: return 'VOICE';
      default: return 'TEXT';
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _mediaFile = File(image.path));
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery, maxDuration: Duration(seconds: 60));
    if (video != null) {
      setState(() {
        _mediaFile = File(video.path);
        _duration = 60; // Default; could extract actual duration
      });
    }
  }

  Future<void> _submit() async {
    final success = await ref.read(sparqProvider.notifier).createSparq(
      type: _currentType,
      text: _text,
      backgroundColor: _currentType == 'TEXT' ? _backgroundColor : null,
      audience: _audience,
      mediaFile: _mediaFile,
      duration: _duration,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sparq created!'),
          backgroundColor: KinrelColors.success,
        ),
      );
      context.pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create Sparq'),
          backgroundColor: KinrelColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sparqState = ref.watch(sparqProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        title: Text('Create Sparq', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: Icon(Icons.image), text: 'Image'),
            Tab(icon: Icon(Icons.videocam), text: 'Video'),
            Tab(icon: Icon(Icons.text_fields), text: 'Text'),
            Tab(icon: Icon(Icons.mic), text: 'Voice'),
          ],
          labelColor: KinrelColors.orange,
          unselectedLabelColor: KinrelColors.textSilver,
          indicatorColor: KinrelColors.orange,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildImageTab(),
                _buildVideoTab(),
                _buildTextTab(),
                _buildVoiceTab(),
              ],
            ),
          ),
          _buildAudienceToggle(),
          _buildSubmitButton(sparqState),
        ],
      ),
    );
  }

  Widget _buildImageTab() {
    return Center(
      child: _mediaFile != null && _currentType == 'IMAGE'
          ? Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_mediaFile!, height: 300, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 8, right: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: Icon(Icons.close, color: Colors.white, size: 18),
                      onPressed: () => setState(() => _mediaFile = null),
                    ),
                  ),
                ),
              ],
            )
          : GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  color: KinrelColors.elevation1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate, size: 48, color: KinrelColors.orange),
                    SizedBox(height: 8),
                    Text('Pick from Gallery', style: TextStyle(color: KinrelColors.textSilver, fontSize: 13)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildVideoTab() {
    return Center(
      child: _mediaFile != null && _currentType == 'VIDEO'
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam, size: 64, color: KinrelColors.orange),
                SizedBox(height: 8),
                Text('Video selected', style: TextStyle(color: KinrelColors.textSilver)),
                TextButton(
                  onPressed: () => setState(() => _mediaFile = null),
                  child: Text('Remove', style: TextStyle(color: KinrelColors.error)),
                ),
              ],
            )
          : GestureDetector(
              onTap: _pickVideo,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  color: KinrelColors.elevation1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_library, size: 48, color: KinrelColors.orange),
                    SizedBox(height: 8),
                    Text('Pick Video (max 60s)', style: TextStyle(color: KinrelColors.textSilver, fontSize: 13)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 120,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _parseColor(_backgroundColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _text = v),
              maxLines: 3,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Type something...',
                hintStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ),
          SizedBox(height: 16),
          Text('Background Color', style: TextStyle(color: KinrelColors.textSilver, fontSize: 13)),
          SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _bgColors.length,
              separatorBuilder: (_, __) => SizedBox(width: 8),
              itemBuilder: (context, index) {
                final color = _bgColors[index];
                final isSelected = color == _backgroundColor;
                return GestureDetector(
                  onTap: () => setState(() => _backgroundColor = color),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _parseColor(color),
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTapDown: (_) => setState(() => _isRecording = true),
            onTapUp: (_) => setState(() {
              _isRecording = false;
              _duration = 10; // Simulated recording duration
            }),
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? KinrelColors.error : KinrelColors.orange,
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          SizedBox(height: 12),
          Text(
            _isRecording ? 'Release to stop' : 'Hold to record (max 60s)',
            style: TextStyle(color: KinrelColors.textSilver, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceToggle() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('Audience:', style: TextStyle(color: KinrelColors.textSilver, fontSize: 13)),
          SizedBox(width: 12),
          ChoiceChip(
            label: Text('Everyone'),
            selected: _audience == 'PUBLIC',
            selectedColor: KinrelColors.orange.withValues(alpha: 0.2),
            onSelected: (_) => setState(() => _audience = 'PUBLIC'),
          ),
          SizedBox(width: 8),
          ChoiceChip(
            label: Text('Family Only'),
            selected: _audience == 'FAMILY_ONLY',
            selectedColor: KinrelColors.orange.withValues(alpha: 0.2),
            onSelected: (_) => setState(() => _audience = 'FAMILY_ONLY'),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(SparqState state) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: state.isCreating ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: KinrelColors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: state.isCreating
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Text('Uploading...', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                  ],
                )
              : Text('Post Sparq', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 16)),
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return KinrelColors.orange;
    }
  }
}
