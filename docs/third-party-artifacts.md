# Third-party artifacts and kmod signing

Rule: the public image carries **only code and metadata**. Binaries under a
restrictive licence are generated locally, from a pinned manifest, with SHA-256
verification. This is an engineering policy, not legal advice.

## What goes where

| Artifact | Licence | Public image | Local only |
| --- | --- | --- | --- |
| `gpu_unlock.ko` (Zagitta/gpu-unlock, built and signed in CI) | GPL-2.0 | yes, via `build.yml` -> `kmod-sign.yml` -> `modules/gpu-unlock` (after the proof below) | n/a |
| NVIDIA firmware (`gsp_ga10x.bin`, booter, derived V67 image) | NVIDIA Driver License Agreement | never | generated from the pinned package (`firmware/artifacts-*.json` upstream) |
| `kmod.der` (public certificate) | n/a | yes, `files/system/etc/pki/silver-goggles/` | n/a |
| signing private key | secret | never | CI secret + encrypted offline backup |

Firmware provenance and the open licence question are in the upstream
`firmware/NOTICE.md`. Redistribution of the NVIDIA binaries is **not** claimed
and not done here.

## Signing key custody

- CI secret `KMOD_SIGNING_KEY` lives in the GitHub environment `kmod-signing`
  (required reviewer, `main` only). Only `kmod-sign.yml` reads it.
- `scripts/sign-kmod.sh` fails closed: empty secret, key not matching
  `kmod.der`, unsigned output, or an already-signed input are all errors. There is no
  unsigned fallback.
- Fork and PR runs have no access to the environment secret, so no module is signed.
- Offline backup: `~/mok.key.gpg` (symmetric AES256). Verify it by decrypting
  and comparing the public-key SHA-256 with `kmod.der`. Keep a second copy
  off the machine.

## Failure paths

| Situation | Action |
| --- | --- |
| Secret missing or empty | `sign-kmod.sh` exits 1; set it with `gh secret set KMOD_SIGNING_KEY -R <repo> --env kmod-signing < key.pem` |
| Key does not match `kmod.der` | exits 1 with both fingerprints; fix the secret, not the cert |
| `kernel-devel` for the base kernel unavailable | workflow fails at "Resolve kernel"; wait for the base to publish or pin an older base |
| Base kernel bumped | `kmod-sign.yml` builds against the pinned base digest on every image build, so the module follows the kernel. If the build or sign job fails, `modules/gpu-unlock` skips with a warning and the image ships **without** the unlock (`ujust gpu-unlock-setup` then refuses) |
| Job runs on a PR / merge queue | the sign job is skipped (`github.ref` is not main); image builds without the unlock |
| Key leaked or lost | generate a new pair, commit the new `kmod.der`, `ujust enroll-silver-goggles-key` on each host, `mokutil --delete` the old one, rotate the secret |
| Annual hygiene | rotate the key and re-enrol |

## Updating the pinned source

`GPU_UNLOCK_REF` in `.github/workflows/kmod-sign.yml` pins the gpu-unlock
commit. It currently points at the `add-ga106m-2560` branch commit (upstream PR
#160). Move it to an upstream commit when that PR, or an equivalent, lands.

## Status

Nothing below has run yet: `kmod-sign.yml` (now called from `build.yml`),
`modules/gpu-unlock` and `ujust gpu-unlock-setup`. Firmware reaches the initramfs via
`rpm-ostree initramfs-etc --track=/etc/gpu-unlock` plus the `firmware_class.path` karg
(not a dracut module: `initramfs --enable` runs dracut inside the new deployment tree,
where host-local /etc is likely not visible; inferred from the rpm-ostree source, unproven). Open questions to prove on the first main build:
the container job under `ubuntu-latest`, `actions/download-artifact` staging into
the BlueBuild context, whether the initramfs-etc overlay delivers the firmware early enough for the module. Until the artifact loads
on the host, the plaintext local key must not be deleted. The `kmod-signing`
environment must be restricted to the `main` branch and have no required
reviewer, otherwise image builds stall or skip the unlock.
