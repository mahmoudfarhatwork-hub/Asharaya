#!/usr/bin/env bash
# docs_update.sh — يسجّل التغيير في CHANGELOG.md ويعمل commit (بنفس الوصف كتعليق) ثم push.
# الاستخدام:  bash docs_update.sh "وصف التغيير"
# بيضيف README.md و CHANGELOG.md فقط (مش بيلمس باقي الملفات).
set -e

MSG="$1"
if [ -z "$MSG" ]; then
  echo "اكتب وصف التغيير:  bash docs_update.sh \"وصف التغيير\""
  exit 1
fi
if [ ! -f CHANGELOG.md ] || [ ! -f README.md ]; then
  echo "شغّل السكريبت من جذر الريبو (فيه README.md و CHANGELOG.md)."
  exit 1
fi

TODAY=$(date +%Y-%m-%d)
ENTRY="- ${TODAY} · ${MSG}"

# أضف السطر تحت عنوان "## Unreleased" مباشرة
awk -v entry="$ENTRY" '
  { print }
  /^## Unreleased/ && !done { print entry; done=1 }
' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md

git add README.md CHANGELOG.md
if git diff --cached --quiet; then
  echo "مفيش تغييرات تتسجل."
  exit 0
fi
git commit -m "docs: ${MSG}"
git push
echo "✅ اتسجل ورُفع: docs: ${MSG}"
