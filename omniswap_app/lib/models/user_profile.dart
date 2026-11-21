class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String whatsappNumber;
  final String country;
  final String city;
  final String area;
  final double rating;

  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.whatsappNumber,
    required this.country,
    required this.city,
    required this.area,
    required this.rating,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      whatsappNumber: json['whatsapp_number'] as String,
      country: json['country'] as String,
      city: json['city'] as String,
      area: json['area'] as String,
      rating: (json['rating'] as num).toDouble(),
    );
  }
}