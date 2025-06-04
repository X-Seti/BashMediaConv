pkgname=stripmeta
pkgver=1.0.0
pkgrel=1
pkgdesc="Strip metadata from media files and rename to .m4v"
arch=('any')
url="https://example.com"
license=('MIT')
depends=('exiftool' 'mkvtoolnix-cli' 'ffmpeg')
source=('stripmeta.sh' 'stripmeta.desktop')
md5sums=('SKIP' 'SKIP')

package() {
  install -Dm755 stripmeta.sh "$pkgdir/usr/local/bin/stripmeta"
  install -Dm644 stripmeta.desktop "$pkgdir/usr/share/applications/stripmeta.desktop"
}
