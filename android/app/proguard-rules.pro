# Flutter's own keep rules are added by the Flutter Gradle plugin, and
# plugins ship their own consumer rules. flutter_secure_storage v11 encrypts
# with javax.crypto directly, so its bundled Tink dependency is unused and
# is left for R8 to strip; these only silence missing-annotation warnings.
-dontwarn com.google.crypto.tink.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
