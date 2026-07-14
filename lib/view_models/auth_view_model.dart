import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../repositories/user_repository.dart';
import '../models/user_model.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final UserRepository _userRepository = UserRepository();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }


  Future<String?> registerUser({
    required String name,
    required String email,
    required String password,
    required String mobileNumber,
    required String profileType,
    required double burnoutThreshold,
  }) async {
    _setLoading(true);

    bool isPasswordValid(String password) {
      if (password.length < 8) return false; // 至少 8 个字符
      if (!password.contains(RegExp(r'[A-Z]'))) return false; // 至少一个大写字母
      if (!password.contains(RegExp(r'[a-z]'))) return false; // 至少一个小写字母
      if (!password.contains(RegExp(r'[0-9]'))) return false; // 至少一个数字
      if (!password.contains(RegExp(r'[!@#\$&*~?]'))) return false; // 至少一个特殊字符
      return true;
    }

    try {
      // 1. 调用底层的 AuthService 在 Firebase Auth 创建账号
      UserCredential credential = await _authService.signUpWithEmailAndPassword(email, password);

      if (credential.user != null) {
        // 2. 账号创建成功后，封装成 UserModel 对象
        UserModel newUser = UserModel(
          uid: credential.user!.uid,
          name: name,
          email: email,
          mobileNumber: mobileNumber,
          profileType: profileType,
          burnoutThreshold: burnoutThreshold,
        );
        // 3. 调用 UserRepository 存入 Firestore 数据库
        await _userRepository.createUserProfile(newUser);
      }
      _setLoading(false);
      return null; // 返回 null 代表没有任何错误，注册成功
    } catch (e) {
      _setLoading(false);
      return e.toString(); // 返回错误讯息让 UI 弹窗显示
    }
  }

  // 处理登录 (FR 1.2)
  Future<String?> loginUser(String email, String password) async {
    _setLoading(true);
    try {
      await _authService.signInWithEmailAndPassword(email, password);
      _setLoading(false);
      return null;
    } catch (e) {
      _setLoading(false);
      return e.toString();
    }
  }

  // 处理重置密码 (FR 1.3)
  Future<String?> resetPassword(String email) async {
    _setLoading(true);
    try {
      await _authService.sendPasswordReset(email);
      _setLoading(false);
      return null;
    } catch (e) {
      _setLoading(false);
      return e.toString();
    }
  }
}