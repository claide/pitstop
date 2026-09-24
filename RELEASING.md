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
   git clone git@github.com:claide/homebrew-tap.git
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
./scripts/release.sh 0.3.0
```
This bumps the version, tags `v0.3.0`, pushes, and updates the formula's URL and checksum in
`../homebrew-tap`. Test it on your own Mac first:

```bash
brew install claide/tap/pitstop
pitstop app install
```

**If you also use `./scripts/bundle.sh --install` for local dev on the same Mac**, it links
`pitstop` on your PATH straight to your local build inside `/Applications/Pitstop.app`, which
overrides Homebrew's own link to the Cellar build. When that happens, `pitstop app install`
silently reinstalls your old local build instead of the new release, and the popover keeps
showing the old version no matter how many times you upgrade. Check which one currently owns
the command:

```bash
readlink "$(which pitstop)"
```

If it points into `/Applications/Pitstop.app/...` instead of `/opt/homebrew/Cellar/pitstop/...`,
reclaim it before testing a release:

```bash
brew unlink pitstop && brew link --overwrite pitstop
```

## What teammates run

Install:
```bash
brew install claide/tap/pitstop
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