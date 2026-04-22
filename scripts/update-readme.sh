#!/usr/bin/env bash
set -euo pipefail

USERNAME="Greite"
README="README.md"

# Language colors for shields.io badges
declare -A LANG_COLORS=(
  [Go]="00ADD8" [TypeScript]="3178C6" [PHP]="777BB4" [JavaScript]="F7DF1E"
  [Shell]="89E051" [HTML]="E34F26" [CSS]="1572B6" [Dockerfile]="384D54"
  [Python]="3776AB" [Ruby]="CC342D" [Rust]="DEA584" [Vue]="4FC08D"
  [Java]="ED8B00" [C]="A8B9CC" [Makefile]="427819" [Astro]="555555"
  [Twig]="555555" [Nix]="5277C3" [Dart]="0175C2" [Swift]="F05138"
  [Kotlin]="7F52FF" [Lua]="2C2D72" [SCSS]="CC6699"
)

# ---------- Fetch data ----------

echo "Fetching repos..."
REPO_DATA=$(gh api "users/${USERNAME}/repos?per_page=100" --paginate)

# Non-fork repos only
OWN_REPOS=$(echo "$REPO_DATA" | jq '[.[] | select(.fork == false)]')

# ---------- Top Projects ----------

TOP_PROJECTS=$(echo "$OWN_REPOS" | jq -r '
  sort_by(-.stargazers_count) | .[0:5] | to_entries[] |
  "| \(.key + 1) | **[\(.value.name)](https://github.com/'"${USERNAME}"'/\(.value.name))** | \(.value.description // "-" | gsub("\\|"; "\\\\|")) | \(.value.stargazers_count) |"
')

TOP_PROJECTS_CONTENT="## 🏆 Top Projects

| | Project | Description | ⭐ |
|---|---------|-------------|----|
${TOP_PROJECTS}"

# ---------- Recent Activity ----------

RECENT=$(echo "$OWN_REPOS" | jq -r '
  [.[] | select(.name != "'"${USERNAME}"'")] |
  sort_by(.pushed_at) | reverse | .[0:5][] |
  {
    name: .name,
    desc: (.description // "-" | gsub("\\|"; "\\\\|")),
    date: (.pushed_at | split("T")[0])
  } |
  "| **[\(.name)](https://github.com/'"${USERNAME}"'/\(.name))** | \(.desc) | `\(.date)` |"
')

RECENT_ACTIVITY_CONTENT="## 🕐 Activité récente

| Project | Description | Last Push |
|---------|-------------|-----------|
${RECENT}"

# ---------- Languages ----------

echo "Fetching languages..."
TMPFILE=$(mktemp)
for repo in $(echo "$OWN_REPOS" | jq -r '.[].name'); do
  gh api "repos/${USERNAME}/${repo}/languages" 2>/dev/null >> "$TMPFILE" || true
done

LANG_JSON=$(jq -s 'map(to_entries[]) | group_by(.key) | map({lang: .[0].key, bytes: (map(.value) | add)}) | sort_by(-.bytes)' "$TMPFILE")
rm -f "$TMPFILE"

TOTAL_BYTES=$(echo "$LANG_JSON" | jq '[.[].bytes] | add // 0')

LANG_BADGES=""
if [ "$TOTAL_BYTES" -gt 0 ]; then
  while IFS=$'\t' read -r lang pct; do
    color="${LANG_COLORS[$lang]:-555555}"
    encoded_lang=$(echo "$lang" | sed 's/ /%20/g; s/#/%23/g; s/+/%2B/g')
    LANG_BADGES+="  <img src=\"https://img.shields.io/badge/${encoded_lang}-${pct}%25-${color}?style=flat-square\" alt=\"${lang}\" />\n"
  done < <(echo "$LANG_JSON" | jq -r '.[] | select((.bytes / '"$TOTAL_BYTES"') > 0.01) | [.lang, ((.bytes / '"$TOTAL_BYTES"' * 1000 | round) / 10 | tostring)] | @tsv')
fi

LANGUAGES_CONTENT="## 🔤 Languages

<p align=\"center\">
${LANG_BADGES}</p>"

# ---------- Replace sections in README ----------

replace_section() {
  local tag="$1"
  local content_file="$2"
  local file="$3"

  local tmp
  tmp=$(mktemp)

  awk -v tag="$tag" -v cfile="$content_file" '
    BEGIN { printing=1; replaced=0 }
    $0 ~ "<!-- " tag ":START -->" {
      print; printing=0; replaced=1
      while ((getline line < cfile) > 0) print line
      next
    }
    $0 ~ "<!-- " tag ":END -->" { printing=1 }
    printing { print }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}

# Write each section to temp files
TOP_FILE=$(mktemp)
RECENT_FILE=$(mktemp)
LANG_FILE=$(mktemp)

echo "$TOP_PROJECTS_CONTENT" > "$TOP_FILE"
echo "$RECENT_ACTIVITY_CONTENT" > "$RECENT_FILE"
echo -e "$LANGUAGES_CONTENT" > "$LANG_FILE"

replace_section "TOP_PROJECTS" "$TOP_FILE" "$README"
replace_section "RECENT_ACTIVITY" "$RECENT_FILE" "$README"
replace_section "LANGUAGES" "$LANG_FILE" "$README"

rm -f "$TOP_FILE" "$RECENT_FILE" "$LANG_FILE"

echo "README updated successfully!"
