import 'package:geolocator/geolocator.dart';

class PollingUnitGpsFix {
  const PollingUnitGpsFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
}

class PollingUnitVerificationService {
  const PollingUnitVerificationService();

  Future<PollingUnitGpsFix> captureCurrentFix() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError(
        'Location services are disabled on this device.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError(
        'Location permission was not granted.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is permanently disabled for USESF.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 25),
      ),
    );

    return PollingUnitGpsFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      capturedAt: position.timestamp,
    );
  }
}
