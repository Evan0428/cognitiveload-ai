import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttermoji/fluttermoji.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// Virtual Avatar service (Chua Yi Zhe).
///
/// On-device ML Kit face detection on a selfie, then samples the photo to seed
/// as many cartoon-avatar (fluttermoji) attributes as the phone can read for
/// free: skin tone, hair colour, facial hair and expression. Hair STYLE and
/// gender aren't detectable on-device, so those stay as quick manual picks in
/// the editor. Config is persisted locally and mirrored to Firestore.
class AvatarService {
  // fluttermoji SkinColor list order (fluttermojimodel.dart) with representative
  // hex tones. Index here == the index fluttermoji stores for 'skinColor'.
  static const List<int> _skinHex = [
    0xFFDBB4, // 0 White
    0xEDB98A, // 1 Peach
    0x614335, // 2 Black
    0xD08B5B, // 3 Brown
    0xAE5D29, // 4 DarkBrown
    0xF8D25C, // 5 Yellow
    0xFD9841, // 6 Tanned
  ];

  // fluttermoji HairColor list order with representative hex.
  static const List<int> _hairHex = [
    0xA55728, // 0 Auburn
    0x2C1B18, // 1 Black
    0x724133, // 2 Brown
    0xB58143, // 3 Blonde
    0xD6B370, // 4 BlondeGolden
    0x4A312C, // 5 BrownDark
    0xF59797, // 6 PastelPink
    0xECDCBF, // 7 Platinum
    0xC93305, // 8 Red
    0xC8C8C8, // 9 SilverGray
  ];

  // FacialHairType: 0 Nothing, 1 Full Beard, 2 Beard Light, 3/4 moustaches.
  static const int _fhNone = 0, _fhFull = 1, _fhLight = 2;
  // MouthType: 8 Smile, 1 Default.
  static const int _mouthSmile = 8, _mouthDefault = 1;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(enableClassification: true),
  );

  FluttermojiController get _controller =>
      Get.isRegistered<FluttermojiController>()
          ? Get.find<FluttermojiController>()
          : Get.put(FluttermojiController());

  Future<bool> hasAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fluttermojiSelectedOptions') != null;
  }

  /// Detect a face in [image] and seed skin, hair colour, facial hair and
  /// expression. Returns true if a usable photo was processed.
  Future<bool> seedFromSelfie(File image) async {
    try {
      final faces =
          await _detector.processImage(InputImage.fromFilePath(image.path));
      final im = img.decodeImage(await image.readAsBytes());
      if (im == null) return false;

      final Rect? box = faces.isNotEmpty ? faces.first.boundingBox : null;
      final smiling = faces.isNotEmpty
          ? (faces.first.smilingProbability ?? 0.0)
          : 0.0;

      final options = await _controller.getFluttermojiOptions();

      // --- Skin tone (cheek) ---
      final skin = _avgColor(im, box, 0.30, 0.55, 0.70, 0.80);
      if (skin != null) {
        options['skinColor'] = _nearest(skin, _skinHex);
      }

      // --- Hair colour (strip just above the forehead) ---
      final hair = _avgColor(im, box, 0.20, -0.28, 0.80, -0.05);
      if (hair != null && skin != null && _dist(hair, skin) > 1600) {
        // Only override if the region isn't just skin (bald / hair tied back).
        options['hairColor'] = _nearest(hair, _hairHex);
      }

      // --- Facial hair (chin/moustache darker than cheek) ---
      final chin = _avgColor(im, box, 0.32, 0.82, 0.68, 1.02);
      if (chin != null && skin != null) {
        final darker = _luma(skin) - _luma(chin);
        if (darker > 55) {
          options['facialHairType'] = _fhFull;
        } else if (darker > 28) {
          options['facialHairType'] = _fhLight;
        } else {
          options['facialHairType'] = _fhNone;
        }
      }

      // --- Expression ---
      options['mouthType'] =
          smiling > 0.6 ? _mouthSmile : _mouthDefault;

      await _apply(options);
      return true;
    } catch (e) {
      debugPrint('Avatar face seed failed: $e');
      return false;
    }
  }

  /// Persist a whole option map and refresh the live preview (local + cloud).
  Future<void> _apply(Map<String?, int> options) async {
    final c = _controller;
    c.selectedOptions = Map<String?, dynamic>.from(options);
    await c.setFluttermoji(); // persists + sets the reactive fluttermoji.value
    c.updatePreview(); // force-regenerate the SVG so the preview refreshes
    await saveToCloud();
  }

  /// Average colour of a rectangular region expressed as fractions of the face
  /// box (or the whole image if [box] is null). Fractions may be negative /
  /// > 1 to reach above the forehead or below the chin. Returns null if too
  /// few valid (non shadow/highlight) pixels were found.
  int? _avgColor(
      img.Image im, Rect? box, double fx0, double fy0, double fx1, double fy1) {
    final double bx = box?.left ?? 0, by = box?.top ?? 0;
    final double bw = box?.width ?? im.width.toDouble();
    final double bh = box?.height ?? im.height.toDouble();

    int x0 = (bx + bw * fx0).round().clamp(0, im.width - 1);
    int x1 = (bx + bw * fx1).round().clamp(0, im.width - 1);
    int y0 = (by + bh * fy0).round().clamp(0, im.height - 1);
    int y1 = (by + bh * fy1).round().clamp(0, im.height - 1);
    if (x1 < x0) { final t = x0; x0 = x1; x1 = t; }
    if (y1 < y0) { final t = y0; y0 = y1; y1 = t; }

    int r = 0, g = 0, b = 0, n = 0;
    for (int y = y0; y <= y1; y += 2) {
      for (int x = x0; x <= x1; x += 2) {
        final p = im.getPixel(x, y);
        final rr = p.r.toInt(), gg = p.g.toInt(), bb = p.b.toInt();
        final mx = max(rr, max(gg, bb));
        if (mx < 25 || mx > 250) continue; // skip near-black / blown pixels
        r += rr; g += gg; b += bb; n++;
      }
    }
    if (n < 8) return null;
    return ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
  }

  int _nearest(int rgb, List<int> palette) {
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < palette.length; i++) {
      final d = _dist(rgb, palette[i]);
      if (d < bestDist) {
        bestDist = d.toDouble();
        best = i;
      }
    }
    return best;
  }

  double _dist(int a, int b) {
    final ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
    final br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
    return (pow(ar - br, 2) + pow(ag - bg, 2) + pow(ab - bb, 2)).toDouble();
  }

  double _luma(int rgb) {
    final r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
    return 0.299 * r + 0.587 * g + 0.114 * b;
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
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
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

  void dispose() => _detector.close();
}
