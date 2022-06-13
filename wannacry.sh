#!/bin/bash

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <source dir> <destination dir>"
  exit 1
fi

SRC_DIR=$1
DST_DIR=$2

mkdir -p "$DST_DIR"

for f in "$SRC_DIR"/*; do
  dst_f="$DST_DIR/"$(basename "$f")
  gpg -c -o "$dst_f" --batch --passphrase "encrypt me" "$f"
done
