import 'package:geolocator/geolocator.dart';

class LocationUnavailable implements Exception {
  final String message;
  final bool openSettings;
  LocationUnavailable(this.message, {this.openSettings = false});
  @override
  String toString() => message;
}

class LocationService {
  /// Anything worse than this and the geofence check is meaningless — a 200 m
  /// error circle would clear almost any radius we set.
  static const double maxAcceptableAccuracyMeters = 50;

  /// Resolves a usable fix or throws [LocationUnavailable] with a message that
  /// tells the borrower what to do about it.
  Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationUnavailable(
        'Turn on location to capture progress.',
        openSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationUnavailable('Allow location access to capture progress.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationUnavailable(
        'Location is blocked for this app. Enable it in phone settings.',
        openSettings: true,
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  /// Streams fixes so the capture screen can show live accuracy and only arm
  /// the shutter once the borrower is genuinely inside the geofence.
  Stream<Position> watch() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 2,
        ),
      );

  double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  Future<void> openSettings() => Geolocator.openLocationSettings();
}