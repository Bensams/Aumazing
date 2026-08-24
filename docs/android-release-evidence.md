# Android Release Evidence

The `Android Release Evidence` workflow is the repeatable build record for
capstone demonstrations and validator distribution. It runs on pull requests
that change the mobile app or shared packages and can also be started manually.

Each run records:

- Flutter dependency resolution
- Static analysis
- Full Flutter test suite
- Release APK build
- Release Android App Bundle build

The workflow uploads both artifacts under a commit-specific name. The artifact
metadata should be retained with the defense evidence folder together with the
run URL, commit SHA, Flutter version, tester/device matrix, and signed test
installation result.

The repository's Android Gradle configuration uses the configured release
keystore when `android/key.properties` is supplied by the build environment.
Without that file, local builds use the debug signing key so contributors can
verify packaging; the resulting artifact must not be distributed as a signed
production release. Production CI should provide the keystore through a
protected secret or runner file and record the signing identity separately,
without committing keys or passwords.
