/// A therapy/SPED center listing from the directory.
class TherapyCenter {
  const TherapyCenter({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.description,
    this.city = 'Davao City',
    this.phone,
    this.services = const [],
  });

  final String id;
  final String name;
  final String? description;
  final String address;
  final String city;
  final double latitude;
  final double longitude;
  final String? phone;
  final List<String> services;

  factory TherapyCenter.fromMap(Map<String, dynamic> map) {
    return TherapyCenter(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      address: map['address'] as String? ?? '',
      city: map['city'] as String? ?? 'Davao City',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      phone: map['phone'] as String?,
      services: (map['services'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'address': address,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'phone': phone,
        'services': services,
      };
}

/// A center paired with its distance from the parent's position (km).
class RankedTherapyCenter {
  const RankedTherapyCenter({required this.center, required this.distanceKm});

  final TherapyCenter center;
  final double distanceKm;
}
