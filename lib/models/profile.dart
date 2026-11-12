enum UserRole { chofer, admin }

UserRole roleFromString(String value) =>
    value == 'admin' ? UserRole.admin : UserRole.chofer;

class Profile {
  final String id;
  final String? fullName;
  final String? phone;
  final UserRole role;

  const Profile({
    required this.id,
    required this.role,
    this.fullName,
    this.phone,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String?,
      phone: map['phone'] as String?,
      role: roleFromString(map['role'] as String? ?? 'chofer'),
    );
  }

  bool get isAdmin => role == UserRole.admin;
}
