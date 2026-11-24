import 'package:connectivity_plus/connectivity_plus.dart';
import 'upload_scheduler.dart';

/// Maps connectivity_plus results to domain NetworkConnectionType.
NetworkConnectionType mapConnectivity(List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.wifi)) {
    return NetworkConnectionType.wifi;
  }
  if (results.contains(ConnectivityResult.ethernet)) {
    return NetworkConnectionType.ethernet;
  }
  if (results.contains(ConnectivityResult.mobile)) {
    return NetworkConnectionType.cellular;
  }
  return NetworkConnectionType.none;
}

/// Service providing current connectivity state and updates stream.
class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<NetworkConnectionType> check() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return mapConnectivity(results);
    } catch (_) {
      return NetworkConnectionType.none;
    }
  }

  Stream<NetworkConnectionType> watch() {
    return _connectivity.onConnectivityChanged.map(mapConnectivity);
  }
}
