# Maintainer: GitHub Copilot <noreply@github.com>

_repo=download-organizer-linux
pkgname=download-organizer-git
pkgver=r8.308e9cf
pkgrel=1
pkgdesc='Linux-native Bash script that sorts Downloads into categorized folders'
arch=('any')
url='https://github.com/budi-imam-prasetyo/download-organizer-linux'
license=('unknown')
depends=(
  'bash'
  'coreutils'
  'findutils'
  'sed'
  'util-linux'
  'xdg-user-dirs'
)
makedepends=('git')
optdepends=('xdg-user-dirs: automatic Downloads folder detection')
provides=('download-organizer')
conflicts=('download-organizer')
source=("$_repo::git+$url.git#branch=main")
sha256sums=('SKIP')

pkgver() {
  cd "$_repo"
  printf 'r%s.%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)"
}

package() {
  cd "$_repo"

  install -Dm755 organize-downloads.sh "$pkgdir/usr/share/download-organizer/organize-downloads.sh"
  install -Dm644 lib/core.sh "$pkgdir/usr/share/download-organizer/lib/core.sh"
  install -Dm644 lib/routing.sh "$pkgdir/usr/share/download-organizer/lib/routing.sh"
  install -Dm644 lib/undo.sh "$pkgdir/usr/share/download-organizer/lib/undo.sh"

  install -Dm644 config/extensions.conf "$pkgdir/usr/share/download-organizer/config/extensions.conf"

  install -Dm755 /dev/stdin "$pkgdir/usr/bin/download-organizer" <<'EOF'
#!/usr/bin/env bash
export LOG_DIR="${LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/download-organizer}"
exec /usr/share/download-organizer/organize-downloads.sh "$@"
EOF

  install -Dm644 systemd/download-organizer.timer "$pkgdir/usr/lib/systemd/user/download-organizer.timer"
  install -Dm644 /dev/stdin "$pkgdir/usr/lib/systemd/user/download-organizer.service" <<'EOF'
[Unit]
Description=Daily trigger for Download Organizer
Documentation=file:///usr/share/doc/download-organizer/README.md file:///usr/share/doc/download-organizer/README.id.md

[Service]
Type=oneshot
ExecStart=/usr/bin/download-organizer
Environment=LOG_DIR=%h/.local/state/download-organizer
StandardOutput=journal
StandardError=journal
SyslogIdentifier=download-organizer
ProtectSystem=strict
ReadWritePaths=%h/Downloads %h/.local/state/download-organizer
Restart=no

[Install]
WantedBy=default.target
EOF

  install -Dm644 README.md "$pkgdir/usr/share/doc/download-organizer/README.md"
  install -Dm644 README.id.md "$pkgdir/usr/share/doc/download-organizer/README.id.md"
}