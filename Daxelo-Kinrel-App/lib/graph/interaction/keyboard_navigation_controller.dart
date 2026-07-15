// lib/graph/interaction/keyboard_navigation_controller.dart
//
// DAXELO KINREL — Keyboard Navigation Controller (P4.4)
//
// Per Vision §11 HP-7 + §5 Layer 3 — real keyboard navigation wiring.
// Wraps the canvas in a Focus widget and handles:
//   Arrow keys → pan camera (50px per press, spring-animated per P3.1)
//   +/-        → zoom in/out (20% per press, spring-animated)
//   Tab        → navigate to next node (sets keyboardFocusedNodeId)
//   Shift+Tab  → navigate to previous node
//   Enter      → focus the keyboard-focused node (same as tap)
//   Escape     → clear keyboard focus + selection
//
// The keyboardFocusedNodeId is distinct from focusedPersonId (the
// cinematic focus from P2.1). Keyboard focus is a wayfinding state —
// it highlights which node will receive Enter — without triggering the
// cinematic camera pull until Enter is pressed.
//
// WCAG 2.1.2 (No Keyboard Trap): the Escape key always clears focus.
// Tab/Shift+Tab cycle through all visible nodes. The graph never traps
// keyboard focus — the user can always Tab out to the next focusable
// widget in the tree.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_controller.dart';

/// Riverpod state holding the keyboard-focused node ID. Distinct from
/// `selectedNodeProvider` (which tracks tap selection) and
/// `graphFocusProvider.focusedPersonId` (which tracks cinematic focus).
///
/// When the user presses Tab, this cycles through visible node IDs.
/// When the user presses Enter, the engine treats it as a tap on the
/// keyboard-focused node.
final keyboardFocusedNodeProvider = StateProvider<String?>((ref) => null);

/// Handles keyboard events for the graph canvas. Returns `true` if the
/// event was handled (prevents it from propagating to the platform),
/// `false` otherwise.
///
/// The handler is a free function (not a class) so it can be called
/// from any Focus widget's onKeyEvent callback. It receives the
/// [camera], [ref], [viewportSize], [visibleNodeIds] (ordered list of
/// currently visible node IDs for Tab cycling), and [onFocusNode]
/// (callback to focus the Enter-pressed node — typically the same as
/// tapping it).
bool handleGraphKeyEvent({
  required KeyEvent event,
  required CameraController camera,
  required WidgetRef ref,
  required Size viewportSize,
  required List<String> visibleNodeIds,
  required void Function(String nodeId) onFocusNode,
  required BuildContext context,
}) {
  if (event is! KeyDownEvent) return false;
  final key = event.logicalKey;

  // Arrow keys → pan (50px per press).
  const panStep = 50.0;
  if (key == LogicalKeyboardKey.arrowLeft) {
    camera.panBySpring(panStep, 0);
    return true;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    camera.panBySpring(-panStep, 0);
    return true;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    camera.panBySpring(0, panStep);
    return true;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    camera.panBySpring(0, -panStep);
    return true;
  }

  // +/- → zoom (20% per press).
  if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) {
    camera.zoomIn(viewportSize: viewportSize);
    return true;
  }
  if (key == LogicalKeyboardKey.minus ||
      key == LogicalKeyboardKey.numpadSubtract) {
    camera.zoomOut(viewportSize: viewportSize);
    return true;
  }

  // Tab → cycle to next node. Shift+Tab → cycle to previous.
  if (key == LogicalKeyboardKey.tab) {
    if (visibleNodeIds.isEmpty) return false;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final current = ref.read(keyboardFocusedNodeProvider);
    int index = current == null ? -1 : visibleNodeIds.indexOf(current);
    if (isShift) {
      index = index <= 0 ? visibleNodeIds.length - 1 : index - 1;
    } else {
      index = (index + 1) % visibleNodeIds.length;
    }
    ref.read(keyboardFocusedNodeProvider.notifier).state =
        visibleNodeIds[index];
    return true;
  }

  // Enter → focus the keyboard-focused node (same as tap).
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    final nodeId = ref.read(keyboardFocusedNodeProvider);
    if (nodeId != null) {
      onFocusNode(nodeId);
      return true;
    }
    return false;
  }

  // Escape → clear keyboard focus + selection. WCAG 2.1.2 (No Keyboard
  // Trap): Escape always works, even if no node is focused.
  if (key == LogicalKeyboardKey.escape) {
    ref.read(keyboardFocusedNodeProvider.notifier).state = null;
    return true;
  }

  return false;
}
