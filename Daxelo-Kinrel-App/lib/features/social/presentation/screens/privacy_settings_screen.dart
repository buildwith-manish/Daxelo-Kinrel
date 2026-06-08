import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../data/providers/privacy_provider.dart';

class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(privacyProvider.notifier).fetchSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final privacyState = ref.watch(privacyProvider);

    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        title: Text('Privacy', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Profile Privacy
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KinrelColors.elevation1,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Profile Privacy',
                            style: TextStyle(color: KinrelColors.textWhite, fontSize: 16, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('When enabled, new followers must send a request instead of following you directly',
                            style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (privacyState.isProfileLoading)
                      SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange),
                      )
                    else
                      Switch(
                        value: privacyState.isPrivate,
                        activeColor: KinrelColors.orange,
                        onChanged: (value) async {
                          final success = await ref.read(privacyProvider.notifier).toggleProfilePrivacy(value);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success ? 'Profile privacy updated' : 'Failed to update'),
                                backgroundColor: success ? KinrelColors.success : KinrelColors.error,
                              ),
                            );
                          }
                        },
                      ),
                  ],
                ),
                if (privacyState.profileError != null)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(privacyState.profileError!,
                      style: TextStyle(color: KinrelColors.error, fontSize: 12)),
                  ),
              ],
            ),
          ),
          SizedBox(height: 16),

          // Family Tree Visibility
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KinrelColors.elevation1,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Family Tree Visibility',
                            style: TextStyle(color: KinrelColors.textWhite, fontSize: 16, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('When disabled, non-members cannot view your family tree graph',
                            style: TextStyle(color: KinrelColors.textDim, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (privacyState.isGraphLoading)
                      SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange),
                      )
                    else
                      Switch(
                        value: privacyState.isFamilyGraphPublic,
                        activeColor: KinrelColors.orange,
                        onChanged: (value) async {
                          final success = await ref.read(privacyProvider.notifier).toggleFamilyGraphVisibility(value);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success ? 'Tree visibility updated' : 'Failed to update'),
                                backgroundColor: success ? KinrelColors.success : KinrelColors.error,
                              ),
                            );
                          }
                        },
                      ),
                  ],
                ),
                if (privacyState.graphError != null)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(privacyState.graphError!,
                      style: TextStyle(color: KinrelColors.error, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
