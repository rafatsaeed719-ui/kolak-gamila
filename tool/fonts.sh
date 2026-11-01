#!/usr/bin/env bash
# خطوط البرنامج (IBM Plex Sans Arabic) وخط الفواتير (Amiri)
set -e
mkdir -p assets/fonts
for w in Regular Bold; do
  curl -fsSL -o assets/fonts/Amiri-$w.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/amiri/Amiri-$w.ttf"
done
for w in Regular Medium SemiBold Bold; do
  curl -fsSL -o assets/fonts/IBMPlexSansArabic-$w.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexsansarabic/IBMPlexSansArabic-$w.ttf"
done
ls -la assets/fonts
