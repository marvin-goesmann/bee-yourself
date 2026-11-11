#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
.build/release/BeeMeadow --record recording/frames
ffmpeg -loglevel error -y -framerate 30 -i recording/frames/f%05d.png -vf "scale=1440:1080:flags=neighbor,format=yuv420p" -c:v libx264 -preset slow -crf 22 -tune animation -movflags +faststart -an site/gameplay.mp4
ffmpeg -loglevel error -y -i recording/frames/f00230.png -vf "scale=1440:1080:flags=neighbor" -q:v 3 site/poster.jpg
echo "Updated site/gameplay.mp4"
