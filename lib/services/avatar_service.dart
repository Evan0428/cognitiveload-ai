import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttermoji/fluttermoji.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Virtual Avatar service (Chua Yi Zhe).
///
/// The user builds and customises their cartoon avatar (fluttermoji) during
/// onboarding and from Settings. The config is persisted locally and mirrored
/// to the Firestore user profile so it follows them across devices.
class AvatarService {
  /// True once the user has created/customised an avatar.
  Future<bool> hasAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fluttermojiSelectedOptions') != null;
  }

  /// Mirror the current avatar config to the Firestore user profile.
  Future<void> saveToCloud() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final options = prefs.getString('fluttermojiSelectedOptions');
    if (options == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'avatarOptions': options}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Avatar cloud save failed (kept local): $e');
    }
  }

  /// Restore the avatar from Firestore on a fresh device/install. Does not
  /// clobber a locally-edited avatar.
  Future<void> loadFromCloud() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('fluttermojiSelectedOptions') != null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final options = doc.data()?['avatarOptions'] as String?;
      if (options == null) return;
      await prefs.setString('fluttermojiSelectedOptions', options);
      await prefs.setString('fluttermoji',
          FluttermojiFunctions().decodeFluttermojifromString(options));
      if (Get.isRegistered<FluttermojiController>()) {
        // restoreState() is declared `void ... async`, so it can't be awaited.
        Get.find<FluttermojiController>().restoreState();
      }
    } catch (e) {
      debugPrint('Avatar cloud load failed: $e');
    }
  }
}
