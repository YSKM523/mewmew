# TestFlight Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a complete fastlane and GitHub Actions path that signs `com.tensorproxies.mewmew`, builds it, and uploads it to TestFlight.

**Architecture:** fastlane owns App Store Connect authentication, match signing, build-number allocation, deterministic manual profile selection, archive/export, and upload. GitHub Actions validates all required secrets, supplies an SSH agent and an ephemeral keychain, prepares Rust/XcodeGen artifacts, and invokes the lane.

**Tech Stack:** Ruby/Bundler, fastlane (`match`, `gym`, `pilot`), GitHub Actions, XcodeGen, SwiftUI, Rust/UniFFI.

## Global Constraints

- Do not create an App Store Connect app record or Bundle ID.
- Bundle identifier is exactly `com.tensorproxies.mewmew`.
- The match repository is exactly `git@github.com:YSKM523/mewmew-certs.git`.
- Do not hard-code the Apple team ID.
- Do not commit, push, write secret material to repository files, or modify unrelated user changes.
- Linux verification must parse every changed YAML file and run `ruby -c` on every Ruby file.

---

### Task 1: Define the configuration acceptance check

**Files:**
- Test: command-line Python and shell assertions (no persistent test fixture)

**Interfaces:**
- Consumes: the requested secret names, fastlane action names, bundle identifier, and signing mode.
- Produces: a repeatable check that fails until all delivery files have the required structure.

- [ ] **Step 1: Run a failing preflight assertion**

```bash
python3 - <<'PY'
from pathlib import Path
required = [
    Path("ios/fastlane/Appfile"),
    Path("ios/fastlane/Matchfile"),
    Path("ios/fastlane/Fastfile"),
    Path("ios/Gemfile"),
]
missing = [str(path) for path in required if not path.exists()]
assert not missing, f"missing delivery files: {', '.join(missing)}"
PY
```

Expected: non-zero exit with the missing fastlane/Gemfile paths.

### Task 2: Add fastlane configuration

**Files:**
- Create: `ios/fastlane/Appfile`
- Create: `ios/fastlane/Matchfile`
- Create: `ios/fastlane/Fastfile`
- Create: `ios/Gemfile`

**Interfaces:**
- Consumes: `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_P8`, `APPSTORE_TEAM_ID`, `MATCH_PASSWORD`, `MATCH_KEYCHAIN_NAME`, and `MATCH_KEYCHAIN_PASSWORD`.
- Produces: `bundle exec fastlane beta`, which authenticates, syncs signing, selects the next build number with a zero fallback, archives with the matched profile, and uploads with a short-SHA changelog.

- [ ] **Step 1: Add Appfile, Matchfile, Fastfile, and Gemfile**

Use only documented action parameters. Keep match writable, use the SSH certificates repository, map `SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING` explicitly into `export_options.provisioningProfiles`, and pass the same profile to archive signing.

- [ ] **Step 2: Run the configuration acceptance check**

Expected: all file, secret-name, action-name, bundle-ID, profile-mapping, and manual-signing assertions pass.

### Task 3: Wire GitHub Actions and XcodeGen signing

**Files:**
- Modify: `.github/workflows/ios.yml`
- Modify: `ios/project.yml`

**Interfaces:**
- Consumes: the six repository secrets and the fastlane files from Task 2.
- Produces: a tag/manual-only TestFlight job with explicit missing-secret failures, SSH deploy-key access, an ephemeral keychain, Rust Apple targets, XcodeGen, generated XCFramework/project files, and the beta lane invocation.

- [ ] **Step 1: Replace the TestFlight skeleton**

Validate `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_P8`, `APPSTORE_TEAM_ID`, `MATCH_PASSWORD`, and `MATCH_DEPLOY_KEY`; fail once per missing name. Then configure `webfactory/ssh-agent`, GitHub host keys, Ruby/Bundler, Rust targets, XcodeGen, generated build inputs, an ephemeral keychain, and run `bundle exec fastlane beta`.

- [ ] **Step 2: Set application signing style to manual**

Add only `CODE_SIGN_STYLE: Manual` to the application target settings; supply the team dynamically from the CI secret through fastlane.

### Task 4: Verify the completed delivery path

**Files:**
- Verify: `.github/workflows/ios.yml`
- Verify: `ios/project.yml`
- Verify: `ios/fastlane/Appfile`
- Verify: `ios/fastlane/Matchfile`
- Verify: `ios/fastlane/Fastfile`
- Verify: `ios/Gemfile`

**Interfaces:**
- Consumes: all implementation files.
- Produces: fresh syntax and structure evidence for the final report.

- [ ] **Step 1: Parse all changed YAML**

```bash
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/ios.yml
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' ios/project.yml
```

- [ ] **Step 2: Check all Ruby syntax**

```bash
ruby -c ios/fastlane/Appfile
ruby -c ios/fastlane/Matchfile
ruby -c ios/fastlane/Fastfile
ruby -c ios/Gemfile
```

- [ ] **Step 3: Re-run the full acceptance check and inspect the scoped diff**

Expected: every assertion passes, all syntax commands exit zero, and the diff contains no secret values, deploy-key files, commits, or unrelated edits.
