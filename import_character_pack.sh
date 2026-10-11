#!/usr/bin/env bash
# import_character_pack.sh — يجرد باك الشخصيات (Modular Character Outfits) وينسخ منه ملفات glTF للمشروع.
# الاستخدام (من جذر الريبو، في Codespace أو على جهازك):
#   bash import_character_pack.sh [مسار-الزيب]            # جرد فقط → character_pack_inventory.txt
#   bash import_character_pack.sh [مسار-الزيب] --copy      # جرد + نسخ glTF/GLB والتكستشرز لمجلد المشروع
# لو ما حطيتش مسار، بيحاول ينزّله من Drive بـ gdown (لازم الملف يكون "أي شخص معاه الرابط").
set -e

FILE_ID="1iP4ECYK1LsZImwRphP1iq2X5qpWf2E4z"
ZIP="${1:-Modular_Character_Outfits.zip}"
[ "$ZIP" = "--copy" ] && ZIP="Modular_Character_Outfits.zip"
DO_COPY=0
for a in "$@"; do [ "$a" = "--copy" ] && DO_COPY=1; done

PROJECT="godot_project_FINAL"
DEST="$PROJECT/assets/characters/modular_pack"
WORK="$(mktemp -d)"
OUT="character_pack_inventory.txt"

if [ ! -f "$ZIP" ]; then
  echo "⬇️  الزيب مش موجود محليًا — بحاول أنزّله من Drive..."
  pip install -q gdown
  gdown "$FILE_ID" -O "$ZIP" || {
    echo "❌ التنزيل فشل (غالبًا الملف مش متشارك بالرابط). نزّله يدويًا من Drive وشغّل: bash $0 مسار-الزيب"
    exit 1
  }
fi

echo "📦 فك الضغط..."
unzip -q "$ZIP" -d "$WORK"

{
  echo "=== جرد باك الشخصيات ($(date +%F)) ==="
  echo
  echo "--- عدد الملفات حسب الامتداد ---"
  find "$WORK" -type f | sed 's/.*\.//' | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn
  echo
  echo "--- المجلدات (مستوى 1-3) ---"
  (cd "$WORK" && find . -maxdepth 3 -type d | sort)
  echo
  echo "--- ملفات glTF/GLB (الحجم بالـ KB) ---"
  find "$WORK" -type f \( -iname '*.glb' -o -iname '*.gltf' \) -printf '%s\t%P\n' | sort -k2 | awk -F'\t' '{printf "%8.0f KB  %s\n", $1/1024, $2}'
  echo
  echo "--- ملفات اسمها فيه (male/female/body/head/hair/outfit/skeleton) ---"
  (cd "$WORK" && find . -type f \( -iname '*male*' -o -iname '*female*' -o -iname '*body*' -o -iname '*head*' -o -iname '*hair*' -o -iname '*outfit*' -o -iname '*skeleton*' \) | sort | head -200)
  echo
  echo "--- أي ملف نصي فيه تعليمات/ترخيص ---"
  (cd "$WORK" && find . -type f \( -iname '*license*' -o -iname '*readme*' -o -iname '*.txt' \) | sort | head -20)
} > "$OUT"

echo "✅ الجرد اتكتب في: $OUT"
echo "   ابعتهولي (ملف نصي صغير) وأنا أظبط CharacterAssembly على أسماء الملفات الفعلية."

if [ "$DO_COPY" = "1" ]; then
  SIZE=$(find "$WORK" -type f \( -iname '*.glb' -o -iname '*.gltf' -o -iname '*.bin' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | du -ch --files0-from=- | tail -1 | cut -f1)
  echo "📁 هنسخ glTF/GLB والتكستشرز (الحجم الكلي: $SIZE) إلى $DEST"
  mkdir -p "$DEST"
  DEST_ABS="$(cd "$DEST" && pwd)"
  (cd "$WORK" && find . -type f \( -iname '*.glb' -o -iname '*.gltf' -o -iname '*.bin' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | xargs -0 cp --parents -t "$DEST_ABS")
  echo "✅ اتنسخ. تأكد من الحجم قبل الـ push (GitHub بيرفض أي ملف أكبر من 100MB)."
fi
rm -rf "$WORK"
