import 'package:flutter/material.dart';
import 'package:isl_app/core/services/api_service.dart';
import 'package:isl_app/views/auth/login_screen.dart';
import 'package:isl_app/views/worker/worker_chat_history_screen.dart';
import 'package:isl_app/views/worker/worker_chat_screen.dart';
import 'package:isl_app/widgets/worker/worker_chat_drawer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WORKER DRAWER
//
// `WorkerChatDrawer` needs onNewChat / onOpenSession / onLogout callbacks.
// Inside WorkerChatScreen those directly manipulate the live message list,
// but on every OTHER worker screen (Documents, Alerts, Profile) there's no
// live chat state to manipulate -- the sensible behaviour there is just to
// navigate into the chat feature. This one helper keeps that navigation
// logic in a single place instead of copy-pasted into three screens.
//
// Usage: Scaffold(drawer: buildSharedWorkerDrawer(context), ...)
// ─────────────────────────────────────────────────────────────────────────────
Widget buildSharedWorkerDrawer(BuildContext context) {
  return WorkerChatDrawer(
    // These screens never have a "current" live session of their own.
    currentSessionId: null,

    // "New chat" from outside the chat screen: arm the same fresh-session
    // flag WorkerChatScreen already checks on init (see
    // ApiService.needsFreshChatSession usage in worker_chat_screen.dart),
    // then go to the chat tab -- consistent with how the bottom nav
    // switches tabs (pushReplacement, not stacking screens).
    onNewChat: () async {
      ApiService.needsFreshChatSession = true;
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WorkerChatScreen()),
      );
    },

    // Opening a past session from "Recent": same read-only history view
    // used from inside the chat screen's own drawer.
    onOpenSession: (sessionId, preview) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkerChatHistoryScreen(
            sessionId: sessionId,
            title: preview,
          ),
        ),
      );
    },

    // Same logout sequence as WorkerChatScreen: clear the stored
    // session/tokens, then replace the whole nav stack with LoginScreen
    // so there's no way back via the system back button.
    onLogout: () async {
      await ApiService().clearSession();
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    },
  );
}
