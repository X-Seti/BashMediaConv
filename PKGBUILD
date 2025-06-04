pkgname=stripmeta
pkgver=1.6.0
pkgrel=1
pkgdesc="Strip metadata from media files and rename to .m4v"
arch=('any')
url="https://github.com/X-Seti/BashMediaConv"
license=('MIT')
depends=('exiftool' 'mkvtoolnix-cli' 'ffmpeg')
source=('stripmeta-kde.sh' 'stripmeta.desktop' 'stripmeta.sh' 'stripmeta-wip.sh')
md5sums=('SKIP' 'SKIP')

package() {
  install -Dm755 stripmeta.sh "$pkgdir/opt/stripmeta"
  install -Dm755 stripmeta-kde.sh "$pkgdir/opt/stripmeta"
  install -Dm755 stripmeta-wip.sh "$pkgdir/opt/stripmeta"
  install -Dm644 stripmeta.desktop "$pkgdir/usr/share/applications/stripmeta.desktop"
  install -Dm755 stripmeta.desktop "$pkgdir/home/$USER/.local/share/kservices5/ServiceMenus/stripmeta.desktop"

}
