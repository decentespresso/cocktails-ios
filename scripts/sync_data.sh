#!/bin/bash
# Copies the site's data into the app bundle (Resources/Data, a folder reference):
# the per-book sqlite dbs + side JSON from /d/admin, and every AVIF picture from
# /d/cocktails/img (~4.5 MB in all), so the app browses fully offline.
# Re-run after the site's data or pictures change, then rebuild.
set -euo pipefail
D=${D:-/d}
OUT="$(cd "$(dirname "$0")/.." && pwd)/Resources/Data"
rm -rf "$OUT"; mkdir -p "$OUT/img"
for f in pdt.db deathco.db pdt_similar_taste.json deathco_similar_taste.json ingredient_substitutes.json; do
	cp "$D/admin/$f" "$OUT/"
done
cd "$D/cocktails/img"
for dir in pdt deathco ingredients glasses spirits spirits/pair; do
	mkdir -p "$OUT/img/$dir"
	cp $dir/*.avif "$OUT/img/$dir/" 2>/dev/null || true
done
cp hero.avif hero-*.avif "$OUT/img/"
# the recipe's ingredient strip: each bottle trimmed to itself (ingredients/tc/, one scale: the
# full picture = 216px), so they pack edge to edge
mkdir -p "$OUT/img/ingredients/tc"
cp ingredients/tc/*.jpg "$OUT/img/ingredients/tc/"
# the cocktail photos trimmed on all sides (<book>/tz/): the recipe page's photo on phones,
# beside the title, as the site's pdt_mobile.css shows it
for b in pdt deathco; do mkdir -p "$OUT/img/$b/tz"; cp $b/tz/*.jpg "$OUT/img/$b/tz/"; done
# dark mode's cut-outs (the site's <dir>/dark/[t/]<name>.avif, cocktails/js/dark_img.js), where made
for dir in pdt deathco ingredients spirits; do
	if [ -d "$dir/dark" ]; then
		mkdir -p "$OUT/img/$dir/dark/t"
		cp $dir/dark/*.avif "$OUT/img/$dir/dark/" 2>/dev/null || true
		cp $dir/dark/t/*.avif "$OUT/img/$dir/dark/t/" 2>/dev/null || true
	fi
done
# the book chooser's tour video thumbnail
mkdir -p "$OUT/img/video"
cp video/explainer.jpg "$OUT/img/video/"
# the scale maker's Tare step: a shaker tin on the Half Decent Scale
mkdir -p "$OUT/img/maker"
cp maker/shaker-scale.jpg "$OUT/img/maker/"
# the scale picture on the recipe page's "Make this cocktail" button
cp "$D/img/small/DE-SCALETHIN_V2-75870-add-06_220x142.avif" "$OUT/img/scale-cta.avif"
# the site's translations of every phrase the app shows (live /admin/api/translation, read-only)
python3 "$(dirname "$0")/sync_lang.py"
du -sh "$OUT"
