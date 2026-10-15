# Release preparation — no release authorized

The development changelog is **1.4.1 (unreleased)**. Binary/package versions
remain **1.4.0** / **1.4.0-zig**. Preparing or verifying packages does not
create a release or authorize a tag.

## Required before an authorized release

- [ ] Obtain explicit approval for the version and tag/release creation.
- [ ] Update version fields together, then verify the exact release source.
- [ ] Require a fresh green nine-job GitHub CI run for that source, not a
  previous checkpoint's result. Preserve existing platform-specific known-bug
  boundaries rather than weakening the oracle to make CI pass.
- [ ] Recheck CLI/library version output and release-note selection.
- [ ] Confirm all six baseline-CPU ReleaseFast packages contain the executable,
  static library, public header, README, CHANGELOG, BUGS and license if present.
- [ ] Check archive integrity and SHA256SUMS; execute the native package and
  compile/run a C embedding consumer against its packaged library.
- [ ] Distinguish cross-built packages from locally executed ones. Native and
  emulated platform behavior belongs to CI, not merely a cross-build success.
- [ ] State compatibility accurately: -O0/QBE_COMPAT matches the patched C
  reference and deliberately retains the documented constant-jnz bug; optimized
  levels implement the low-32-bit condition test.
- [ ] Keep remotes/artifacts credential-free and revoke the previously exposed
  credential. Do not include authentication data in handoff archives.

## Portable build policy

Use the pinned Zig toolchain, ReleaseFast and **-Dcpu=baseline**. A compiler
built for the build host's native CPU can trap on another machine even when
its architecture matches. The workflow now requests baseline CPUs explicitly.

Targets: x86_64-linux-musl, aarch64-linux-musl, riscv64-linux-musl,
x86_64-macos, aarch64-macos, x86_64-windows. The default IL target is a separate
policy: explicitly request amd64_win for Windows ABI output.

Local preview results and the exact newly published CI state are recorded
chronologically in HANDOFF.md. Do not infer that this checklist is complete
from the existence of preview archives. No version bump/tag/release has been
performed by this preparation work.
