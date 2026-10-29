#!/bin/sh
# Builds 7thDroid-<version>-<arch>.AppImage in dist/: 7thDroid's scripts plus a zenity 3.44 (GTK 3)
# bundled with sharun. Runs in ghcr.io/pkgforge-dev/archlinux after pkgforge-dev/anylinux-setup-action,
# following pkgforge-dev/Zenity-GTK3-AppImage.
set -eu

ARCH=$(uname -m)
VERSION=$(cat VERSION)
ZENITY_BRANCH=zenity-3-44

pacman -Syu --noconfirm base-devel git itstool libxtst meson xorg-server-xvfb
get-debloated-pkgs gtk3-mini libxml2-mini glycin-mini

rm -rf /tmp/zenity
git clone --depth 1 --branch "$ZENITY_BRANCH" https://gitlab.gnome.org/GNOME/zenity.git /tmp/zenity
meson setup /tmp/zenity/build /tmp/zenity --buildtype=release --prefix=/usr
meson compile -C /tmp/zenity/build
meson install --no-rebuild -C /tmp/zenity/build

export ARCH
export OUTPATH=./dist
export OUTNAME="7thDroid-$VERSION-$ARCH.AppImage"
export DESKTOP="$PWD/packaging/7thDroid.desktop"
export ICON="$PWD/assets/7th-heaven.png"
export MAIN_BIN=zenity
export URUNTIME_PRELOAD=1
# Software rendering only: dialogs draw the same everywhere, gamescope included.
export ALWAYS_SOFTWARE=1

quick-sharun /usr/bin/zenity

mkdir -p AppDir/share/7thdroid
cp -r install.sh menu.sh lib assets LICENSE README.md VERSION AppDir/share/7thdroid/
# Our AppRun replaces sharun's, so sharun's environment is applied to zenity only.
rm -f AppDir/AppRun
cp packaging/AppRun AppDir/AppRun
chmod +x AppDir/AppRun AppDir/share/7thdroid/install.sh AppDir/share/7thdroid/menu.sh

quick-sharun --make-appimage

# Smoke test: unpack the AppImage as DroidDeck does, then run its zenity and scripts.
rm -rf /tmp/check
mkdir -p /tmp/check
cp dist/"$OUTNAME" /tmp/check/
(
  cd /tmp/check
  ./"$OUTNAME" --appimage-extract >/dev/null
  if [ -d squashfs-root ]; then root=$PWD/squashfs-root; else root=$PWD/AppDir; fi
  head -n 1 "$root/AppRun" | grep -qx '#!/bin/bash'
  status=0
  xvfb-run -a "$root/bin/zenity" --info --text=7thDroid --timeout=2 || status=$?
  [ "$status" -eq 5 ] || { echo "zenity did not open a window (exit $status)" >&2; exit 1; }
  bash "$root/share/7thdroid/install.sh" --help >/dev/null
)
echo "Built dist/$OUTNAME"
