#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# deploy_to_github.sh — شغّله جوه GitHub Codespace (أو أي تيرمينال فيه git)
# بيعمل: يرفع مشروع Asharaya على GitHub، يشغّل GitHub Action تلقائي،
#        يستنى لحد ما يخلص، وينزّل ملف الـ APK جاهز على جهازك.
#
# المتطلبات قبل التشغيل:
#   1) افتح Codespace على أي ريبو (فاضي أو جديد) من github.com/codespaces
#   2) ارفع فولدر المشروع (اللي جواه .github/ و godot_project_FINAL/) جوه الـ Codespace
#      أو استنسخه فيه لو موجود في مكان تاني
#   3) شغّل السكريبت ده من جذر الفولدر: bash deploy_to_github.sh
# ═══════════════════════════════════════════════════════════════════════

set -e  # يوقف فورًا لو أي أمر فشل، عشان ما نكملش بحالة غلط

# ── الإعدادات (غيّرها لو محتاج) ──
REPO_NAME="asharaya-game"          # اسم الريبو على GitHub (هيتعمل لو مش موجود)
BRANCH="main"
WORKFLOW_FILE="build.yml"
PROJECT_DIR="."                    # المسار اللي فيه .github و godot_project_FINAL

echo "═══════════════════════════════════════════════════"
echo "  🚀 Asharaya — رفع المشروع وتشغيل GitHub Actions"
echo "═══════════════════════════════════════════════════"

cd "$PROJECT_DIR"

# ── 1) تأكيد وجود الأدوات المطلوبة ──
if ! command -v git &> /dev/null; then
    echo "❌ git مش متثبت. Codespaces بتيجي بيه جاهز عادةً — تأكد إنك فاتح تيرمينال Codespace صح."
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) مش متاح. Codespaces بتيجي بيه جاهز افتراضيًا."
    echo "   لو مش موجود: https://cli.github.com/"
    exit 1
fi

# ── 2) تسجيل الدخول لـ GitHub CLI (لو لسه مش مسجل) ──
if ! gh auth status &> /dev/null; then
    echo "🔑 محتاج تسجّل دخول لـ GitHub الأول..."
    gh auth login
fi

GH_USER=$(gh api user --jq .login)
echo "✅ داخل بحساب: $GH_USER"

# ── 3) بناء أو التأكد من وجود الريبو على GitHub ──
if gh repo view "$GH_USER/$REPO_NAME" &> /dev/null; then
    echo "📦 الريبو موجود بالفعل: $GH_USER/$REPO_NAME"
else
    echo "📦 بنبني ريبو جديد: $REPO_NAME"
    gh repo create "$REPO_NAME" --private --confirm
fi

REPO_URL="https://github.com/$GH_USER/$REPO_NAME.git"

# ── 4) تجهيز git لوكال لو المجلد مش ريبو أصلاً ──
if [ ! -d ".git" ]; then
    echo "🔧 بنعمل git init..."
    git init -b "$BRANCH"
fi

# لو الـ remote مش مظبوط، ظبّطه
if ! git remote get-url origin &> /dev/null; then
    git remote add origin "$REPO_URL"
else
    git remote set-url origin "$REPO_URL"
fi

# ── 5) تأكيد وجود ملف الـ workflow في المكان الصح ──
if [ ! -f ".github/workflows/$WORKFLOW_FILE" ]; then
    echo "❌ ملف .github/workflows/$WORKFLOW_FILE مش موجود!"
    echo "   تأكد إن مجلد .github جوه نفس المكان اللي بتشغّل منه السكريبت."
    exit 1
fi

echo "✅ ملف الـ workflow موجود: .github/workflows/$WORKFLOW_FILE"

# ── 6) Commit ورفع كل حاجة ──
echo "📤 بنرفع الملفات..."
git add -A
if git diff --cached --quiet; then
    echo "ℹ️  مفيش تغييرات جديدة عن آخر رفعة."
else
    git commit -m "Asharaya build $(date '+%Y-%m-%d %H:%M')"
fi

git push -u origin "$BRANCH"

echo "✅ الرفع خلص. الـ Action هيشتغل لوحده تلقائيًا (push trigger)."

# ── 7) استنى الـ workflow run الجديد يبدأ ──
echo "⏳ بنستنى الـ Action يبدأ..."
sleep 8

RUN_ID=$(gh run list --workflow="$WORKFLOW_FILE" --branch="$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId')

if [ -z "$RUN_ID" ]; then
    echo "⚠️  مقدرش ألاقي run جديد تلقائي. جرّب تشغّله يدوي:"
    echo "    gh workflow run $WORKFLOW_FILE --ref $BRANCH"
    exit 1
fi

echo "🔗 رابط المتابعة: https://github.com/$GH_USER/$REPO_NAME/actions/runs/$RUN_ID"
echo "⏳ بنستنى الـ build يخلص (ده بياخد عادةً 5-10 دقايق)..."

gh run watch "$RUN_ID" --exit-status

echo "✅ الـ Build خلص بنجاح!"

# ── 8) تنزيل الـ APK ونسخ PC تلقائيًا على جهازك ──
DOWNLOAD_DIR="./asharaya_builds_downloaded"
mkdir -p "$DOWNLOAD_DIR"

echo "📥 بننزّل الملفات الناتجة..."
gh run download "$RUN_ID" -D "$DOWNLOAD_DIR"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  🎉 خلصنا! الملفات موجودة في: $DOWNLOAD_DIR"
echo "═══════════════════════════════════════════════════"
find "$DOWNLOAD_DIR" -type f
echo ""
echo "📱 ملف الأندرويد: $DOWNLOAD_DIR/Asharaya-Android-APK/Asharaya.apk"
echo "   (Debug APK — يكفي تمامًا للتجربة واللعب مع الأصحاب، مش موقّع للنشر على Google Play)"
echo "═══════════════════════════════════════════════════"
