# ctop (Cockpit extension) — vendored

- Upstream: https://github.com/ismetozalp/ctop
- Version: 1.1.6
- Release asset: `ctop-1.1.6.zip`
- sha256: `7c89027774d2237bb70f99c5c3e268e85bb926bfec3d5d712c9ab863d69605f2`
- License: Apache-2.0 (see LICENSE)

Vendored instead of downloaded at build time: the release asset returned 504 during a
publish run and blocked the image. A 50 KB static extension does not justify a
network dependency in the build. To update: download the new release asset, verify
its sha256, replace the files here, and bump VERSION/manifest.json.
