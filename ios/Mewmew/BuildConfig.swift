/// Build-time configuration.
///
/// `appToken` is empty in source and rewritten by `scripts/inject-app-token.sh`
/// during CI builds. Xcode's `INFOPLIST_KEY_` mechanism does not carry custom
/// key names into the generated Info.plist, so the value is compiled in
/// instead of read back from the bundle.
///
/// The token throttles the parse worker; it is not user authentication, and it
/// is extractable from the shipped binary either way. Never commit a real one.
enum BuildConfig {
    static let appToken = ""
}
