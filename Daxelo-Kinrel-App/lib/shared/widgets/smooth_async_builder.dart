// lib/shared/widgets/smooth_async_builder.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  SMOOTH ASYNC STATE TRANSITIONS                                      │
// └─────────────────────────────────────────────────────────────────────┘
//
// A reusable wrapper around Riverpod's AsyncValue that cross-fades
// between loading / error / data states instead of hard-cutting. This
// removes the "flash" when a screen's content arrives after a brief
// loading spinner.
//
// Usage:
//   smoothAsyncBuilder<T>(
//     value: ref.watch(myProvider),
//     data: (item) => MyContent(item),
//     loading: () => MySkeleton(),
//     error: (e, _) => MyError(e),
//   )
//
// Or with the widget form:
//   SmoothAsyncBuilder<int>(
//     value: ref.watch(myProvider),
//     data: (item) => MyContent(item),
//     loading: () => MySkeleton(),
//     error: (e, _) => MyError(e),
//   )
//
// Design notes:
//   • Uses AnimatedSwitcher with a 200ms FadeTransition — same duration
//     band as premiumPage so the two feel cohesive.
//   • The switcher keys on the runtimeType of the child widget so it
//     only animates when the state CLASS changes (loading → data), not
//     when the data itself changes (which would cause a cross-fade on
//     every keystroke / refresh).
//   • Zero overhead when the state is stable — AnimatedSwitcher is a
//     no-op when the child doesn't change.
//   • GPU-friendly: FadeTransition uses a single Opacity layer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cross-fades between AsyncValue states (loading / error / data) over
/// 200ms. Use this instead of `value.when()` for screens where the
/// loading→data transition currently causes a visible "flash".
///
/// The cross-fade only triggers when the *state kind* changes (e.g.
/// loading → data), NOT when the data payload changes. This prevents
/// a cross-fade on every refresh / realtime update.
class SmoothAsyncBuilder<T> extends StatelessWidget {
  const SmoothAsyncBuilder({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.error,
    this.duration = const Duration(milliseconds: 200),
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget Function()? loading;
  final Widget Function(Object error, StackTrace? stack)? error;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Key each state's widget on its kind so AnimatedSwitcher only
      // animates when the kind changes (loading → data), NOT when the
      // data payload changes (which would cause a cross-fade on every
      // refresh / realtime update).
      child: value.when(
        data: (d) => KeyedSubtree(
          key: const ValueKey('data'),
          child: data(d),
        ),
        loading: () => KeyedSubtree(
          key: const ValueKey('loading'),
          child: loading?.call() ?? const _DefaultLoading(),
        ),
        error: (e, st) => KeyedSubtree(
          key: const ValueKey('error'),
          child: error?.call(e, st) ?? _DefaultError(error: e),
        ),
      ),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: child,
        );
      },
    );
  }
}

/// A function-style convenience wrapper for callers who prefer the
/// `value.when(...)` shape.
Widget smoothAsyncBuilder<T>({
  required AsyncValue<T> value,
  required Widget Function(T data) data,
  Widget Function()? loading,
  Widget Function(Object error, StackTrace? stack)? error,
  Duration duration = const Duration(milliseconds: 200),
}) {
  return SmoothAsyncBuilder<T>(
    value: value,
    data: data,
    loading: loading,
    error: error,
    duration: duration,
  );
}

class _DefaultLoading extends StatelessWidget {
  const _DefaultLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _DefaultError extends StatelessWidget {
  const _DefaultError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Something went wrong: $error',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
