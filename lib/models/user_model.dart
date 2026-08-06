class UserModel {
  final String uid;
  final String name;
  final String email;
  final String mobileNumber;
  final String profileType;
  final double burnoutThreshold;
  final bool loadThresholdAlert;
  final bool preTaskAlert;
  final bool breakSuggestion;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.mobileNumber,
    required this.profileType,
    required this.burnoutThreshold,
    this.loadThresholdAlert = true,
    this.preTaskAlert = true,
    this.breakSuggestion = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'mobileNumber': mobileNumber,
      'profileType': profileType,
      'burnoutThreshold': burnoutThreshold,
      'loadThresholdAlert': loadThresholdAlert,
      'preTaskAlert': preTaskAlert,
      'breakSuggestion': breakSuggestion,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      mobileNumber: map['mobileNumber'] ?? '',
      profileType: map['profileType'] ?? 'Student',
      burnoutThreshold: (map['burnoutThreshold'] ?? 70.0).toDouble(),
      loadThresholdAlert: map['loadThresholdAlert'] ?? true,
      preTaskAlert: map['preTaskAlert'] ?? true,
      breakSuggestion: map['breakSuggestion'] ?? true,
    );
  }
}