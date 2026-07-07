# Releasing a signed, notarized installer

The [`Release Installer`](../.github/workflows/release-installer.yml) workflow builds `SwiftRepoGUI`,
signs it with your **Developer ID**, wraps it in a signed **`.pkg`** installer, **notarizes** it with
Apple, staples the ticket, and publishes it. The result is an installer anyone can download and run
locally with no Gatekeeper warnings.

## How to cut a release

- **Tag a version** — the installer is attached to a GitHub Release:
  ```sh
  git tag v0.7.6
  git push origin v0.7.6
  ```
- **Or run it on demand** — Actions → *Release Installer* → *Run workflow*. The installer is uploaded
  as a build artifact (not a Release).

## One-time setup

### 1. Certificates (from your Apple Developer account)

You need two **Developer ID** certificates from <https://developer.apple.com/account/resources/certificates>:

- **Developer ID Application** — signs the `.app`.
- **Developer ID Installer** — signs the `.pkg`.

Create both (if you don't have them), then in **Keychain Access** select **both certificates**
(each with its private key), right-click → **Export 2 items…**, and save a single
`certificates.p12` with a password. Base64-encode it for the secret:

```sh
base64 -i certificates.p12 | pbcopy
```

### 2. Notarization key (App Store Connect API key)

At <https://appstoreconnect.apple.com/access/integrations/api> create a **Team Key** (role
*Developer* or higher) and download the `AuthKey_XXXXXXXXXX.p8` **once**. Note the **Key ID** and the
**Issuer ID** shown on that page.

### 3. Add these repository secrets

Settings → Secrets and variables → Actions → *New repository secret*:

| Secret | Value |
| --- | --- |
| `CERTIFICATES_P12` | Base64 of the combined `.p12` from step 1 (the `pbcopy` output). |
| `CERTIFICATES_P12_PASSWORD` | The password you set when exporting the `.p12`. |
| `KEYCHAIN_PASSWORD` | Any random string — used to create the throwaway CI keychain. |
| `APP_STORE_CONNECT_KEY_ID` | The Key ID from step 2. |
| `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID from step 2. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The full contents of the `AuthKey_XXXX.p8` file, including the `-----BEGIN/END PRIVATE KEY-----` lines. |

That's it — no `DEVELOPMENT_TEAM` secret needed; the team ID (`Y453UXCT86`) is baked into the workflow
and `ci/ExportOptions.plist`.

## Requirements & notes

- **Xcode 26.** The project uses Swift 6.2 features (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), so
  the runner must have an **Xcode 26.x** toolchain. The workflow targets `runs-on: macos-26`. If
  GitHub's hosted images don't yet carry Xcode 26, point `runs-on` at a **self-hosted** macOS runner
  that has it.
- **Dependencies** (`SwiftXState`, `Ox0badf00d`, `matrix-swift`, `swift-compositional-init`) are
  fetched from `github.com/gistya/*`. If any of those repos are **private**, add a step to configure
  git auth (e.g. a PAT via `git config --global url."https://x:${{ secrets.GH_PAT }}@github.com/".insteadOf`)
  before the archive step.
- **What the user sees.** The `.pkg` installs `SwiftRepoGUI.app` into `/Applications` and prompts for
  an admin password (standard for a system-wide installer). Because it's notarized and stapled, it
  opens with no "unidentified developer" warning.
- The `Developer ID Installer` and `Developer ID Application` identities are matched by name, so keep
  exactly one of each in the exported `.p12`.
