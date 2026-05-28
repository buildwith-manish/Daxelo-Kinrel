// lib/presentation/screens/legal/terms_of_service_screen.dart
//
// DAXELO KINREL — Terms of Service Screen (P4-F4: Play Store Compliance)
//
// Static terms of service screen. Accessible WITHOUT login via /terms route.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkBackground,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KinrelColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Terms of Service',
          style: const TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: SelectableText(
          _termsOfServiceText,
          style: const TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textSecondary,
            height: 1.75,
          ),
        ),
      ),
    );
  }
}

// ── Terms of Service Content ──────────────────────────────────────────

const String _termsOfServiceText = '''
Terms of Service

Last updated: March 2025

1. Acceptance of Terms

By accessing or using the Daxelo Kinrel application ("Service"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, please do not use the Service.

2. Description of Service

Daxelo Kinrel is a family relationship intelligence application that allows users to build family trees, discover kinship terms across Indian languages, and connect with family members. The Service is provided by Daxelo Technologies Pvt. Ltd. ("Company", "we", "us", or "our").

3. User Accounts

You must create an account to use the Service. You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. You must be at least 13 years old to create an account.

4. User Content

You retain ownership of any content you submit, post, or display on or through the Service ("User Content"). By submitting User Content, you grant us a worldwide, non-exclusive, royalty-free license to use, reproduce, and process such content solely for the purpose of providing the Service.

5. Family Tree Data

Family trees and relationship data you create may be visible to other members you invite. You are responsible for ensuring you have consent from family members before adding their personal information to your family tree. We are not liable for any disputes arising from the addition of family member data.

6. Acceptable Use

You agree not to use the Service to:
   • Violate any applicable laws or regulations
   • Infringe upon the rights of others
   • Submit false or misleading information
   • Harass, abuse, or harm other users
   • Attempt to gain unauthorized access to the Service
   • Use automated systems to access the Service without authorization
   • Upload content that is offensive, obscene, or otherwise objectionable

7. Privacy

Your use of the Service is also governed by our Privacy Policy, which is incorporated by reference into these Terms. Please review our Privacy Policy at https://kinrel.app/privacy or within the app.

8. Intellectual Property

The Service and its original content (excluding User Content), features, and functionality are owned by Daxelo Technologies and are protected by international copyright, trademark, and other intellectual property laws. Our trademarks and trade dress may not be used in connection with any product or service without prior written consent.

9. Payments and Subscriptions

Certain features of the Service may require payment. By purchasing a subscription or making a payment:
   • You agree to the pricing and billing terms displayed at the time of purchase
   • Payments are processed through Razorpay and are subject to their terms
   • Subscriptions auto-renew unless cancelled at least 24 hours before the renewal date
   • Refunds are handled in accordance with applicable law and our refund policy

10. Termination

We may terminate or suspend your account at any time for any reason, including violation of these Terms. Upon termination, your right to use the Service will immediately cease. You may also terminate your account at any time by deleting it through the app settings or by contacting us.

11. Disclaimer of Warranties

The Service is provided on an "AS IS" and "AS AVAILABLE" basis. We make no warranties, expressed or implied, regarding the Service's reliability, accuracy, availability, or fitness for a particular purpose. We do not guarantee that the Service will be uninterrupted, timely, secure, or error-free.

12. Limitation of Liability

To the maximum extent permitted by law, Daxelo Technologies shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of the Service, including but not limited to damages for loss of profits, goodwill, data, or other intangible losses.

13. Indemnification

You agree to indemnify and hold harmless Daxelo Technologies, its officers, directors, employees, and agents from any claims, damages, losses, costs, or expenses arising from your use of the Service or violation of these Terms.

14. Changes to Terms

We reserve the right to modify these Terms at any time. We will notify you of material changes via email or in-app notification. Your continued use of the Service after changes constitutes acceptance of the updated Terms.

15. Governing Law

These Terms shall be governed by and construed in accordance with the laws of India, without regard to conflict of law principles. Any disputes arising from these Terms shall be subject to the exclusive jurisdiction of the courts in Bengaluru, India.

16. Severability

If any provision of these Terms is held to be invalid or unenforceable, the remaining provisions will remain in full force and effect.

17. Contact

For questions about these Terms, please contact us:

Daxelo Technologies Pvt. Ltd.
Email: legal@daxelo.com
Website: https://kinrel.app
''';
