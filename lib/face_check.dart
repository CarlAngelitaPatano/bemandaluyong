import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// ===========================================================================
// Profile-picture security.
//
// Before a photo can become someone's profile picture it must contain a
// clear, real human face. This blocks memes, logos, landscapes, cartoons and
// other random images. Detection runs entirely ON DEVICE (Google ML Kit) —
// the photo never leaves the phone, so it stays private and works offline.
// ===========================================================================

/// Result of checking a candidate profile photo.
enum FaceCheck {
  ok, // exactly one clear human face — allowed
  noFace, // no human face found — blocked
  multipleFaces, // more than one person — blocked
  tooSmall, // a face, but too small/far away to be a good profile pic
  failed, // detector could not run (allowed, so users are never stuck)
}

extension FaceCheckMessage on FaceCheck {
  /// Friendly explanation shown to the user when a photo is rejected.
  String get message => switch (this) {
        FaceCheck.ok => 'Face verified',
        FaceCheck.noFace =>
          'No human face detected. Please use a clear photo of your face — '
              'memes, logos and other images aren\'t allowed as profile pictures.',
        FaceCheck.multipleFaces =>
          'More than one face detected. Please use a photo of just yourself.',
        FaceCheck.tooSmall =>
          'Your face is too small in this photo. Please use a closer shot so '
              'your face is clearly visible.',
        FaceCheck.failed => 'Could not check the photo.',
      };
}

class FaceCheckService {
  FaceCheckService._();

  /// Verifies that [imagePath] shows exactly one clear human face.
  static Future<FaceCheck> check(String imagePath) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.1, // ignore tiny background faces
      ),
    );
    try {
      final faces = await detector.processImage(InputImage.fromFilePath(imagePath));

      if (faces.isEmpty) return FaceCheck.noFace;
      if (faces.length > 1) return FaceCheck.multipleFaces;

      // A real profile picture should have a reasonably sized face.
      final face = faces.first;
      if (face.boundingBox.width < 60 || face.boundingBox.height < 60) {
        return FaceCheck.tooSmall;
      }
      return FaceCheck.ok;
    } catch (_) {
      // Never lock someone out because the detector failed to run.
      return FaceCheck.failed;
    } finally {
      await detector.close();
    }
  }
}
