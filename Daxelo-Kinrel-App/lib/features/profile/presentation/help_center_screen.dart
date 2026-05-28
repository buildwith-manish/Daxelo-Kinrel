// lib/features/profile/presentation/help_center_screen.dart
//
// DAXELO KINREL — Help Center / FAQ Screen
//
// In-app FAQ with searchable, expandable accordion items.
// Dark theme design consistent with the profile section.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_typography.dart';

// ── Design Tokens ──────────────────────────────────────────────────
const Color _bg = Color(0xFF131416);
const Color _cardBg = Color(0xFF191B2C);
const Color _orange = Color(0xFFE8612A);
const Color _textPrimary = Color(0xFFF5F0EE);
const Color _textSecondary = Color(0xFFC9B4A8);
const Color _textDim = Color(0xFF8A7A72);
const Color _borderSubtle = Color(0x0FFFFFFF);

// ── FAQ Data ───────────────────────────────────────────────────────
const List<_FaqItem> _faqItems = [
  _FaqItem(
    question: 'How do I add a family member?',
    answer:
        'Open your family tree and tap the "+" button at the bottom right. '
        'You can add a person by entering their name, date of birth, and '
        'other details. Once added, you can connect them to existing members '
        'using the "Add Relationship" option on their profile card.',
  ),
  _FaqItem(
    question: 'How do I connect two people in my tree?',
    answer:
        'Navigate to either person\'s profile in your family tree, then tap '
        '"Add Relationship." Select the relationship type (parent, child, '
        'sibling, spouse, etc.) and choose the second person from your tree. '
        'Kinrel will automatically create the reciprocal relationship. '
        'For example, if you add A as B\'s parent, B will automatically '
        'appear as A\'s child.',
  ),
  _FaqItem(
    question: 'What are kinship terms?',
    answer:
        'Kinship terms are the words used in different Indian languages to '
        'describe family relationships. For example, "father\'s elder brother" '
        'is called "tau" in Hindi, "pisa" in Bengali, and "peddodu" in Telugu. '
        'Kinrel provides these terms across 14 Indian languages, helping you '
        'understand how to address every family member correctly. Explore the '
        'Kinship Dictionary from the home screen to discover more.',
  ),
  _FaqItem(
    question: 'How do I invite someone to my family?',
    answer:
        'Open your family tree, tap the share icon at the top, and choose '
        '"Invite Member." You can share an invite link via WhatsApp, SMS, or '
        'any messaging app. The invited person will receive a link to join '
        'your family tree. You can also set invite permissions in your profile '
        'settings to control who can invite others.',
  ),
  _FaqItem(
    question: 'Is my family data private?',
    answer:
        'Yes, your data privacy is our top priority. All family data is '
        'encrypted both in transit and at rest. Only members you invite can '
        'see your family tree. You can control your profile visibility '
        '(public/private) and invite permissions from Profile → Privacy & '
        'Security. We never sell or share your personal data with third '
        'parties. You can also request a full data export or delete your '
        'account at any time.',
  ),
  _FaqItem(
    question: 'How do I delete my account?',
    answer:
        'Go to Profile → Privacy & Security → Delete My Account. You\'ll be '
        'asked to confirm by typing "DELETE" and entering your password. '
        'There is a 30-second cooldown before the deletion button becomes '
        'active. Please note that this action is permanent and cannot be '
        'undone. All your profile data, family trees where you are the sole '
        'admin, and relationships will be permanently removed.',
  ),
  _FaqItem(
    question: 'What languages are supported?',
    answer:
        'Kinrel currently supports kinship terms in 14 Indian languages: '
        'Hindi, Bengali, Telugu, Marathi, Tamil, Gujarati, Punjabi, '
        'Malayalam, Kannada, Odia, Assamese, Sindhi, Urdu, and English. '
        'You can set your preferred language in Profile → Preferred Language. '
        'We are continuously working on adding more languages and dialects.',
  ),
];

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _FaqItem {
  const _FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int? _expandedIndex;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_FaqItem> get _filteredItems {
    if (_searchQuery.isEmpty) return _faqItems;
    final query = _searchQuery.toLowerCase();
    return _faqItems.where((item) {
      return item.question.toLowerCase().contains(query) ||
          item.answer.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Help Center',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Search Bar ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: _textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search FAQ...',
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  color: _textDim.withValues(alpha: 0.7),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _textDim,
                  size: 22,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: _textDim, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: _cardBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _orange, width: 1.5),
                ),
              ),
            ),
          ),

          // ── FAQ Count ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  '${filtered.length} question${filtered.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: _textDim,
                  ),
                ),
                const Spacer(),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Text(
                      'Clear search',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: _orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── FAQ List ─────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? _buildNoResults()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      // Map back to original index for expansion tracking
                      final originalIndex = _searchQuery.isEmpty
                          ? index
                          : _faqItems.indexOf(filtered[index]);
                      return _FaqAccordionCard(
                        item: filtered[index],
                        isExpanded: _expandedIndex == originalIndex,
                        onTap: () {
                          setState(() {
                            _expandedIndex = _expandedIndex == originalIndex
                                ? null
                                : originalIndex;
                          });
                        },
                      );
                    },
                  ),
          ),

          // ── Contact Support CTA ──────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/profile/contact-support'),
                  icon: const Icon(Icons.support_agent, size: 20),
                  label: const Text(
                    'Still need help? Contact support',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _orange,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _orange, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color: _orange,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No results found',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: _textDim,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FAQ Accordion Card
// ═══════════════════════════════════════════════════════════════════════

class _FaqAccordionCard extends StatelessWidget {
  const _FaqAccordionCard({
    required this.item,
    required this.isExpanded,
    required this.onTap,
  });

  final _FaqItem item;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded ? _orange.withValues(alpha: 0.3) : _borderSubtle,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Question row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.question,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isExpanded ? _orange : _textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 250),
                      turns: isExpanded ? 0.5 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: isExpanded ? _orange : _textDim,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                // Answer
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      item.answer,
                      style: const TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 14,
                        color: _textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                  sizeCurve: Curves.easeInOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
