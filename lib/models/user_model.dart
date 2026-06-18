class UserModel {
  final String uid;
  final String name;
  final String email;
  final String mobileNumber;
  final String profileType;
  final double burnoutThreshold;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.mobileNumber,
    required this.profileType,
    required this.burnoutThreshold,
  });


  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'mobileNumber': mobileNumber,
      'profileType': profileType,
      'burnoutThreshold': burnoutThreshold,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      mobileNumber: map['mobileNumber'] ?? '',
      profileType: map['profileType'] ?? 'Student',
      burnoutThreshold: (map['burnoutThreshold'] ?? 100.0).toDouble(),
    );
  }
}