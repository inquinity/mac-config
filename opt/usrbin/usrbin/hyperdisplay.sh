#! /bin/zsh

case "$1" in
  "mount" | "m")
    diskutil mount /dev/disk4
    ;;
  * | "unmount" | "u")
    if [ -d /Volumes/HYPERDISPLY ]; then diskutil unmountDisk /Volumes/HYPERDISPLY ; fi
     ;;
esac

