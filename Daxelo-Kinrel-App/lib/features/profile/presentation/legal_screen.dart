// lib/features/profile/presentation/legal_screen.dart
//
// DAXELO KINREL — Legal Screen (Terms of Service / Privacy Policy)
//
// Single widget with a `type` parameter ('terms' or 'privacy').
// Uses WebView to load the remote legal pages, with in-app
// fallback text if the URL fails to load.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/brand_typography.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);

// ── Fallback Legal Text ────────────────────────────────────────────

const String _termsText = '''
Terms of Service

Last updated: January 2025

1. Acceptance of Terms
By accessing or using the Daxelo Kinrel application ("Service"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, please do not use the Service.

2. Description of Service
Daxelo Kinrel is a family relationship intelligence application that allows users to build family trees, discover kinship terms across Indian languages, and connect with family members. The Service is provided by Daxelo Technologies Pvt. Ltd. ("Company", "we", "us", or "our").

3. User Accounts
You must create an account to use the Service. You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. You must be at least 13 years old to create an account.

4. User Content
You retain ownership of any content you submit, post, or display on or through the Service ("User Content"). By submitting User Content, you grant us a worldwide, non-exclusive, royalty-free license to use, reproduce, and process such content solely for the purpose of providing the Service.

5. Family Tree Data
Family trees and relationship data you create may be visible to other members you invite. You are responsible for ensuring you have consent from family members before adding their personal information to your family tree.

6. Acceptable Use
You agree not to use the Service to:
   - Violate any applicable laws or regulations
   - Infringe upon the rights of others
   - Submit false or misleading information
   - Harass, abuse, or harm other users
   - Attempt to gain unauthorized access to the Service
   - Use automated systems to access the Service

7. Privacy
Your use of the Service is also governed by our Privacy Policy, which is incorporated by reference into these Terms.

8. Intellectual Property
The Service and its original content (excluding User Content), features, and functionality are owned by Daxelo Technologies and are protected by international copyright, trademark, and other intellectual property laws.

9. Termination
We may terminate or suspend your account at any time for any reason, including violation of these Terms. Upon termination, your right to use the Service will immediately cease.

10. Disclaimer of Warranties
The Service is provided on an "AS IS" and "AS AVAILABLE" basis. We make no warranties, expressed or implied, regarding the Service's reliability, accuracy, availability, or fitness for a particular purpose.

11. Limitation of Liability
To the maximum extent permitted by law, Daxelo Technologies shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of the Service.

12. Changes to Terms
We reserve the right to modify these Terms at any time. We will notify you of material changes via email or in-app notification. Your continued use of the Service after changes constitutes acceptance of the updated Terms.

13. Governing Law
These Terms shall be governed by and construed in accordance with the laws of India, without regard to conflict of law principles.

14. Contact
For questions about these Terms, please contact us at legal@daxelokinrel.com.
''';

const String _privacyText = '''
Privacy Policy

Last updated: January 2025

1. Introduction
Daxelo Technologies Pvt. Ltd. ("Company", "we", "us", or "our") operates the Daxelo Kinrel application ("Service"). This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our Service.

2. Information We Collect
Personal Information: When you create an account, we collect your name, email address, phone number (optional), and date of birth (optional).
Family Data: Information you add about family members, including names, relationships, and dates.
Usage Data: We collect information about how you access and use the Service, including device information, IP address, browser type, and pages visited.
Communications: If you contact our support team, we collect the content of your communications.

3. How We Use Your Information
We use collected information to:
   - Provide, maintain, and improve the Service
   - Create and manage your account
   - Process your family tree data and compute relationships
   - Send you notifications about family activity
   - Respond to your inquiries and support requests
   - Monitor and analyze usage patterns
   - Detect, prevent, and address technical issues and fraud

4. Data Sharing
We do not sell your personal information. We may share your information only in the following circumstances:
   - With family members you invite to your family tree
   - With service providers who assist in operating the Service
   - When required by law or to protect our legal rights
   - In connection with a business transfer or acquisition

5. Data Security
We implement appropriate technical and organizational security measures to protect your personal information, including encryption in transit and at rest, access controls, and regular security audits. However, no method of transmission over the Internet is 100% secure.

6. Data Retention
We retain your personal information for as long as your account is active or as needed to provide the Service. You can request deletion of your account and associated data at any time through the app settings.

7. Your Rights
You have the right to:
   - Access your personal information
   - Correct inaccurate information
   - Request deletion of your data
   - Export your data in a machine-readable format
   - Withdraw consent for data processing
   - Object to processing of your personal information

8. Cookies and Tracking
We use cookies and similar tracking technologies to monitor activity on our Service and hold certain information. You can instruct your browser to refuse all cookies or to indicate when a cookie is being sent.

9. Children's Privacy
The Service is not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13. If we discover such information, we will delete it immediately.

10. International Data Transfers
Your information may be transferred to and processed in countries other than your country of residence. We ensure appropriate safeguards are in place for such transfers.

11. Changes to This Privacy Policy
We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the "Last updated" date.

12. Contact Us
If you have any questions about this Privacy Policy, please contact us at privacy@daxelokinrel.com.
''';

class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.type});

  /// 'terms' or 'privacy'
  final String type;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _loadFailed = false;

  bool get _isTerms => widget.type == 'terms';

  String get _title => _isTerms ? 'Terms of Service' : 'Privacy Policy';

  String get _url => _isTerms
      ? 'https://daxelokinrel.com/legal/terms'
      : 'https://daxelokinrel.com/legal/privacy';

  String get _fallbackText => _isTerms ? _termsText : _privacyText;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (_) {
            if (mounted && !_loadFailed) {
              setState(() {
                _isLoading = false;
                _loadFailed = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _title,
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // If WebView failed to load, show fallback text
    if (_loadFailed) {
      return _buildFallbackText();
    }

    return Stack(
      children: [
        // WebView
        WebViewWidget(controller: _controller),

        // Loading indicator
        if (_isLoading)
          Container(
            color: _bg,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(_orange),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading $_title...',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFallbackText() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Offline notice
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _orange.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined, color: _orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Could not load from server. Showing in-app version.',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: _textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Legal text content
          SelectableText(
            _fallbackText,
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: _textSecondary,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}
