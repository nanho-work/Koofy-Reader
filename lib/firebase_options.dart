// Configuration derived from the supplied Firebase Android/iOS registration files.
// Public client identifiers, not server credentials. The admin Web app lives in Quiz_Site.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class ReaderFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return ios;
    throw UnsupportedError(
      'Firebase is configured for the Android and iOS reader only.',
    );
  }

  static const android = FirebaseOptions(
    apiKey: "AIzaSyBOsARbPg3YEJmR1jR3RuHRspuUABNQnKI",
    appId: "1:573216627685:android:6232369a4ed4009eb72d0c",
    messagingSenderId: "573216627685",
    projectId: "koofy-reader",
    storageBucket: "koofy-reader.firebasestorage.app",
  );

  static const ios = FirebaseOptions(
    apiKey: "AIzaSyAIuSQFsq46X6YvLzUy00zs8_T7wYBp58o",
    appId: "1:573216627685:ios:a36b79e708cb9e64b72d0c",
    messagingSenderId: "573216627685",
    projectId: "koofy-reader",
    storageBucket: "koofy-reader.firebasestorage.app",
    iosBundleId: "com.koofylab.koofyreader",
  );
}
