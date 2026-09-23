import 'offline_status.dart';

/// Native build: the whole app is installed on the device, so there is
/// nothing to save for offline play.
class OfflineWebService {
  const OfflineWebService();

  bool get isSupported => false;

  Future<OfflineStatus?> status() async => null;

  Future<OfflineStatus?> downloadAll({
    void Function(int done, int total)? onProgress,
  }) async => null;
}
