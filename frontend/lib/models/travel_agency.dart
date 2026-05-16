class TravelAgency {
  final String id;
  final String name;
  final String description;
  final String phone;
  final String email;
  final String address;
  final String instagram;
  final String website;
  final List<String> services;
  final double rating;
  final int reviews;
  final String imageUrl;
  final List<String> operatingCities;

  const TravelAgency({
    required this.id,
    required this.name,
    required this.description,
    required this.phone,
    required this.email,
    required this.address,
    required this.instagram,
    required this.website,
    required this.services,
    required this.rating,
    required this.reviews,
    required this.imageUrl,
    required this.operatingCities,
  });

  factory TravelAgency.fromJson(Map<String, dynamic> json) {
    return TravelAgency(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      address: json['address'] ?? '',
      instagram: json['instagram'] ?? '',
      website: json['website'] ?? '',
      services: List<String>.from(json['services'] ?? []),
      rating: (json['rating'] ?? 0.0).toDouble(),
      reviews: json['reviews'] ?? 0,
      imageUrl: json['imageUrl'] ?? '',
      operatingCities: List<String>.from(json['operatingCities'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'phone': phone,
        'email': email,
        'address': address,
        'instagram': instagram,
        'website': website,
        'services': services,
        'rating': rating,
        'reviews': reviews,
        'imageUrl': imageUrl,
        'operatingCities': operatingCities,
      };

  // Mock data - extracted from the agencies in the images
  static final List<TravelAgency> mockAgencies = [
    TravelAgency(
      id: '1',
      name: 'Venture Voyage Treks & Tours',
      description: 'Eco tour agency offering Corporate, Customized and Company Tours with premium transport services.',
      phone: '+92 334 335 3061',
      email: 'ventures@voyagetours.pk',
      address: 'SHOP # LG-10, CANTONMENT SHOPPING MALL, Karachi, Pakistan, 75260',
      instagram: 'venturevoyage.pk',
      website: 'venturevoyage.pk',
      services: [
        'Corporate Tours',
        'Customized Tours',
        'Company Tours',
        'Transport Services',
        'Coasters',
        'Grand Cabins',
        'Sedans',
      ],
      rating: 4.8,
      reviews: 156,
      imageUrl: 'assets/destinations/agency1.jpg',
      operatingCities: ['Karachi', 'Islamabad', 'Lahore', 'Hunza'],
    ),
    TravelAgency(
      id: '2',
      name: 'TN7Sky Tour & Travels',
      description: 'Professional tour agency providing comprehensive tours and rental car services across Pakistan.',
      phone: '+92 310 850 3528',
      email: 'tn7skytourspvtltd@gmail.com',
      address: 'Tarnol Islamabad, Islamabad, 44009',
      instagram: 'tn7sky.tours_pvt_ltd',
      website: 'tn7skytourtravels.store',
      services: [
        'Tours',
        'Rent A Car Service',
        'Trip Planning',
        'Transportation',
        'Holiday Packages',
        'Group Trips',
      ],
      rating: 4.9,
      reviews: 209,
      imageUrl: 'assets/destinations/agency2.png',
      operatingCities: ['Islamabad', 'Rawalpinidi', 'Karachi', 'Lahore', 'Naran-Kaghan', 'Kashmir'],
    ),
  ];
}

