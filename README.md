# Glom

Glom is a database application created by Murray Cumming (GNOME). This fork adds
a macOS (Apple Silicon) port built with MacPorts, PostgreSQL 18 support, and a
function to migrate databases created by earlier PostgreSQL versions.

The patched sources are on the `mac-linux` branch. A Linux (Flatpak) build is
planned.

## macOS (Apple Silicon)

A self-contained `.app` bundle with embedded PostgreSQL 18, a native macOS menu
bar, a light/dark theme with accent colours, and an in-app migration of
databases created by earlier PostgreSQL versions (9.4 to 17).

- Ready-to-run build: see the [Releases](https://github.com/M-Rick/Glom/releases).
- Full build procedure and scripts: [`macOS/README.md`](macOS/README.md).
- The companion libgda fix lives in
  [`M-Rick/libgda`](https://github.com/M-Rick/libgda) (branch `pg18`).

## Original project

The upstream Glom documentation is in [`README`](README). Glom is free software
released under the GPL.
