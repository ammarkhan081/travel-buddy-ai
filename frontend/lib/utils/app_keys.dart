import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global route observer so screens can react when they return to the
/// foreground (e.g. the dashboard re-fetching journey-driven alerts after the
/// user starts, changes, or clears a journey on another screen).
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
