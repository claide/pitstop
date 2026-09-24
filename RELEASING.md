# Releasing Pitstop with Homebrew

Pitstop ships through your own Homebrew tap as a formula. Homebrew builds it from
source on each Mac, so there's nothing to sign yet and macOS doesn't quarantine it.

## One-time setup

1. On GitHub, create two public repos: `pitstop` and `homebrew-tap`.
   The tap repo must be named exactly `homebrew-tap`.
2. Push this project to `pitstop`.
3. Put the tap next to it:
   ```bash
   cd ..
   git clone git@github.com:YOUR_GITHUB_USER/homebrew-tap.git
   mkdir -p homebrew-tap/Formula
   cp pitstop/homebrew-tap/Formula/pitstop.rb homebrew-tap/Formula/
   cp pitstop/homebrew-tap/README.md homebrew-tap/
   cd homebrew-tap && git add . && git commit -m "Add pitstop" && git push
   ```
   (After this, delete the `homebrew-tap/` folder from the pitstop repo; it was only a template.)
4. Put your name in `LICENSE` and a reverse domain you own in `Resources/Info.plist`
   (`CFBundleIdentifier`). Commit.

## Every release

```bash
./scripts/release.sh 0.2.0
```
This bumps the version, tags `v0.2.0`, pushes, and updates the formula's URL and checksum in
`../homebrew-tap`. Test it on your own Mac first:

```bash
brew install YOUR_GITHUB_USER/tap/pitstop
pitstop app install
```

## What teammates run

Install:
```bash
brew install YOUR_GITHUB_USER/tap/pitstop
pitstop app install
```

Update:
```bash
brew update && brew upgrade pitstop && pitstop app install
```

Requirements: macOS 14+ and Xcode Command Line Tools (Homebrew installs these already).
The first install compiles Pitstop, which takes a minute or two.

## Later: signed builds

When you get an Apple Developer account, switch to a cask that downloads a signed, notarized
Pitstop.zip from GitHub Releases. Teammates then install with one command and no build step.
