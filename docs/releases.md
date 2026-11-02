# Releasing updates

RunHub uses Sparkle 2 with an HTTPS appcast at
`https://raw.githubusercontent.com/yumaitau/RunHub/main/appcast.xml`.
The initial appcast is empty: add an entry only after its signed archive is available.

## Signing key

The private Ed25519 key is stored in the maintainer's login Keychain under the account
`au.com.yumait.runhub`. The matching public key is in `RunHub-Info.plist`.
Never commit or upload the private key with a release. Back it up securely using
Sparkle's `generate_keys --account au.com.yumait.runhub -x <secure-path>` command.
On another release machine, import that backup with `-f <secure-path>` instead of
generating a replacement. Existing installations trust the embedded public key.

## Prepare a release

1. Increase both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the app target's
   Debug and Release configurations. Sparkle compares `CFBundleVersion`, so each
   release needs a strictly increasing build number (the current build is 112).
2. Archive and export RunHub with Developer ID signing. Sparkle's framework and nested
   helpers must remain signed; do not strip them from the exported app.
3. Notarise the exported app and staple its ticket. Verify it with:

   ```sh
   codesign --verify --deep --strict /path/to/RunHub.app
   spctl --assess --type execute --verbose /path/to/RunHub.app
   ```

4. Create a directory containing only this release's archive. Use `ditto` to preserve
   framework symlinks and permissions:

   ```sh
   mkdir -p /tmp/runhub-release
   ditto -c -k --sequesterRsrc --keepParent /path/to/RunHub.app /tmp/runhub-release/RunHub.zip
   cp appcast.xml /tmp/runhub-release/appcast.xml
   ```

5. Resolve the pinned Sparkle package to a known location, then generate the signed
   appcast. Replace `vX.Y.Z` with the actual GitHub release tag:

   ```sh
   xcodebuild -resolvePackageDependencies \
     -project RunHub.xcodeproj -scheme RunHub \
     -clonedSourcePackagesDirPath /tmp/runhub-release-packages

   /tmp/runhub-release-packages/artifacts/sparkle/Sparkle/bin/generate_appcast \
     --account au.com.yumait.runhub \
     --download-url-prefix 'https://github.com/yumaitau/RunHub/releases/download/vX.Y.Z/' \
     --maximum-deltas 0 \
     /tmp/runhub-release
   ```

   Sparkle reads the archive's bundle version and minimum macOS version and signs the
   exact ZIP bytes. Inspect the generated enclosure URL and `sparkle:edSignature`.
   Existing entries retain their original download URLs. Do not modify the ZIP after
   signing it. The [Sparkle publishing guide](https://sparkle-project.org/documentation/publishing/)
   describes release notes and additional options.

6. Publish a GitHub release with that exact `RunHub.zip`. Confirm the enclosure URL
   downloads successfully, then copy `/tmp/runhub-release/appcast.xml` over the root
   `appcast.xml` and commit it to `main`. Do not point the feed at a draft release.
7. From an older Sparkle-enabled build in Applications, use **Check for Updates…** and
   verify the version, download, installation, relaunch, and desired runner restoration.
   Also verify the busy-job quit confirmation before updating a machine running jobs.

The appcast and new app binary must be published before updates become available.
Adding Sparkle to this checkout alone does not publish a release.
