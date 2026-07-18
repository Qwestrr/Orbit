import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:circle_map/services/location_service.dart';

void main() {
  group('LocationService access evaluation', () {
    test('returns services-disabled when location services are off', () {
      final result = LocationService.evaluateAccessStatus(
        permission: LocationPermission.whileInUse,
        serviceEnabled: false,
      );

      expect(result, LocationAccessStatus.servicesDisabled);
    });

    test('returns granted when permission and services are both available', () {
      final result = LocationService.evaluateAccessStatus(
        permission: LocationPermission.always,
        serviceEnabled: true,
      );

      expect(result, LocationAccessStatus.granted);
    });
  });
}
