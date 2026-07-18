/// A live aircraft contact from the flight-tracking feed (OpenSky Network
/// by default — see FlightTrackingService for swapping providers).
///
/// Honesty note: not every helicopter appears here. Many police, EMS, and
/// military aircraft don't broadcast ADS-B, or broadcast with a blocked
/// identifier, so this overlay reflects "aircraft currently broadcasting
/// a public position," not "all aircraft in the air."
class AircraftContact {
  final String icao24; // unique aircraft address
  final String? callsign;
  final double lat;
  final double lng;
  final double? altitudeFt;
  final double? headingDegrees;
  final double? groundSpeedKts;
  final int? category;
  final bool onGround;
  final DateTime lastContact;

  AircraftContact({
    required this.icao24,
    this.callsign,
    required this.lat,
    required this.lng,
    this.altitudeFt,
    this.headingDegrees,
    this.groundSpeedKts,
    this.category,
    required this.onGround,
    required this.lastContact,
  });

  factory AircraftContact.fromOpenSkyStateVector(List<dynamic> v) {
    // OpenSky /states/all returns each aircraft as a fixed-order array.
    // Index reference: https://openskynetwork.github.io/opensky-api/rest.html
    return AircraftContact(
      icao24: v[0] as String,
      callsign: (v[1] as String?)?.trim(),
      lng: (v[5] as num?)?.toDouble() ?? 0,
      lat: (v[6] as num?)?.toDouble() ?? 0,
      altitudeFt: ((v[7] as num?)?.toDouble() ?? 0) * 3.28084, // m -> ft
      onGround: v[8] as bool? ?? false,
      groundSpeedKts: ((v[9] as num?)?.toDouble() ?? 0) * 1.94384, // m/s -> kts
      headingDegrees: (v[10] as num?)?.toDouble(),
      category: (v.length > 17 ? v[17] : null) as int?,
      lastContact: DateTime.fromMillisecondsSinceEpoch(
          ((v[4] as num?)?.toInt() ?? 0) * 1000),
    );
  }
}

/// Tracks a takeoff event we detected (onGround flipped false), used to
/// drive the "new helicopter taking off" notification.
class TakeoffEvent {
  final AircraftContact aircraft;
  final double takeoffLat;
  final double takeoffLng;
  final DateTime detectedAt;

  TakeoffEvent({
    required this.aircraft,
    required this.takeoffLat,
    required this.takeoffLng,
    required this.detectedAt,
  });
}

enum AircraftKind {
  helicopter,
  airplane,
  unknown,
}

extension AircraftKindX on AircraftKind {
  String get label {
    switch (this) {
      case AircraftKind.helicopter:
        return 'Helicopter';
      case AircraftKind.airplane:
        return 'Airplane';
      case AircraftKind.unknown:
        return 'Aircraft';
    }
  }
}

extension AircraftContactDisplay on AircraftContact {
  String get tailNumberLabel {
    final value = callsign?.trim();
    return value == null || value.isEmpty ? '' : value.toUpperCase();
  }

  AircraftKind get estimatedKind {
    switch (category) {
      case 8:
        return AircraftKind.helicopter;
      case 2:
      case 3:
      case 4:
      case 5:
      case 6:
      case 7:
        return AircraftKind.airplane;
    }

    return AircraftKind.unknown;
  }

  String get estimatedKindLabel {
    return estimatedKind.label;
  }
}
