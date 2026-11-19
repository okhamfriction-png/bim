#!/bin/sh
# Publie le web sur GitHub Pages : l'appli Flutter à la racine, la version bureau (Svelte) dans /bureau/.
#   bin/pages.sh "message du commit"
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/development/flutter/bin:$PATH"
flutter build web --release --base-href /bim/ -o build/pages
(cd bureau && npm run build)
mkdir -p build/pages/bureau && cp -R bureau/dist/. build/pages/bureau/
cd build/ghp
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R ../pages/. .
git add -A
git commit -q -m "${1:-Bim}"
git -c http.postBuffer=524288000 push -q https://github.com/okhamfriction-png/bim.git gh-pages:gh-pages
