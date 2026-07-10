// lib/features/profile/presentation/account_switcher_sheet.dart
//
// DAXELO KINREL — Account Switcher Bottom Sheet
//
// Shows all signed-in accounts with avatars, allows instant switching,
// adding new accounts, and removing accounts. Similar to Instagram/X/Gmail.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/multi_account_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/brand_colors.dart';

class AccountSwitcherSheet extends ConsumerStatefulWidget {
  const AccountSwitcherSheet({super.key});

  @override
  ConsumerState<AccountSwitcherSheet> createState() => _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends ConsumerState<AccountSwitcherSheet> {
  List<StoredAccount> _accounts = [];
  String? _activeUserId;
  bool _isLoading = true;
  bool _isSwitching = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await MultiAccountService.instance.getAccounts();
    final activeId = await MultiAccountService.instance.getActiveUserId();
    // Also get the current Supabase user (might not be in storage yet)
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null && !accounts.any((a) => a.userId == currentUser.id)) {
      // Current session not saved — add it
      await MultiAccountService.instance.saveCurrentSession();
      _accounts = await MultiAccountService.instance.getAccounts();
    } else {
      _accounts = accounts;
    }
    _activeUserId = activeId ?? currentUser?.id;
    setState(() => _isLoading = false);
  }

  Future<void> _switchAccount(StoredAccount account) async {
    if (account.userId == _activeUserId) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSwitching = true);

    final success = await MultiAccountService.instance.switchToAccount(
      account.userId,
      ref,
    );

    if (mounted) {
      setState(() => _isSwitching = false);
      if (success) {
        Navigator.pop(context);
        // Force a full app refresh by going to home
        context.go('/home');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched to ${account.email}'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not switch — session may have expired. Please sign in again.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _removeAccount(StoredAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Account?'),
        content: Text(
          'Remove ${account.email} from this device? You can sign in again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await MultiAccountService.instance.removeAccount(account.userId);
      await _loadAccounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${account.email}')),
        );
      }
    }
  }

  void _addAccount() {
    Navigator.pop(context);
    // Navigate to sign-in screen with "add account" mode
    context.go('/sign-in?mode=add_account');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              children: [
                Text(
                  'Accounts',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${_accounts.length}/$kMaxAccounts',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else ...[
            // Account list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _accounts.length,
                itemBuilder: (context, index) {
                  final account = _accounts[index];
                  final isActive = account.userId == _activeUserId;

                  return _AccountTile(
                    account: account,
                    isActive: isActive,
                    isSwitching: _isSwitching,
                    onTap: () => _switchAccount(account),
                    onRemove: isActive ? null : () => _removeAccount(account),
                  );
                },
              ),
            ),

            // Divider
            const Divider(height: 1),

            // Add account button
            if (_accounts.length < kMaxAccounts)
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.primary, width: 2),
                  ),
                  child: Icon(Icons.add, color: theme.colorScheme.primary),
                ),
                title: Text(
                  'Add Account',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Sign in with another email or Google',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: _addAccount,
              ),

            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.isActive,
    required this.isSwitching,
    required this.onTap,
    this.onRemove,
  });

  final StoredAccount account;
  final bool isActive;
  final bool isSwitching;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = (account.displayName ?? account.email)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: isActive
            ? KinrelColors.orange.withOpacity(0.15)
            : theme.colorScheme.surfaceContainerHighest,
        backgroundImage: account.avatarUrl != null && account.avatarUrl!.isNotEmpty
            ? NetworkImage(account.avatarUrl!)
            : null,
        child: (account.avatarUrl == null || account.avatarUrl!.isEmpty)
            ? Text(
                initials,
                style: TextStyle(
                  color: isActive ? KinrelColors.orange : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
      ),
      title: Text(
        account.displayName ?? account.email,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          color: isActive ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        account.email,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: isSwitching && isActive
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  Icon(Icons.check_circle, color: KinrelColors.orange, size: 20)
                else if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onRemove,
                    color: theme.colorScheme.outline,
                  ),
              ],
            ),
      onTap: onTap,
    );
  }
}
