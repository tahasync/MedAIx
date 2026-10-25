/// Offline detection for the [OfflineBanner].
///
/// Driven by `connectivity_plus`. Tests override [isOfflineProvider] with a
/// fixed value; the real stream is only subscribed to on a device.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `true` while the device reports no network interface at all.
/// A captive portal or a dead Wi-Fi still counts as "online" here; request
/// failures surface through each screen's error state instead.
final isOfflineProvider = StreamProvider<bool>((ref) async* {
  final Connectivity connectivity = Connectivity();
  bool offline(List<ConnectivityResult> results) =>
      results.isEmpty ||
      results.every((result) => result == ConnectivityResult.none);

  yield offline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(offline);
});
