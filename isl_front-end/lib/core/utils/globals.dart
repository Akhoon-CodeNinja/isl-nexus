import 'package:flutter/material.dart';

/// App-wide constants and small shared globals.
///
/// `appNavigatorKey` lets code outside the widget tree (e.g. inside
/// ApiService, when a session expires) push/pop routes without needing a
/// BuildContext, by referencing `appNavigatorKey.currentState`.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();