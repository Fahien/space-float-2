#!/usr/bin/env bash
set -euo pipefail

printf '\n== Repository ==\n'
pwd

printf '\n== Git status ==\n'
git status --short --branch 2>/dev/null || true

printf '\n== Diff stat ==\n'
git diff --stat 2>/dev/null || true

printf '\n== Changed files ==\n'
git diff --name-only 2>/dev/null || true

printf '\n== Recent commits ==\n'
git log --oneline -n 10 2>/dev/null || true

list_project_instruction_files() {
	local pattern='^(AGENTS\.md|README.*|CONTRIBUTING.*|package\.json|pyproject\.toml|setup\.cfg|tox\.ini|Cargo\.toml|go\.mod|pom\.xml|build\.gradle.*|Makefile|\.github)$'
	local rg_pattern='(^|/)(AGENTS\.md|README[^/]*|CONTRIBUTING[^/]*|package\.json|pyproject\.toml|setup\.cfg|tox\.ini|Cargo\.toml|go\.mod|pom\.xml|build\.gradle[^/]*|Makefile)$|(^|/)\.github/'

	if command -v fd >/dev/null 2>&1; then
		fd --hidden --exclude .git --max-depth 3 --ignore-case --type file --type directory "$pattern" . 2>/dev/null
	elif command -v fdfind >/dev/null 2>&1; then
		fdfind --hidden --exclude .git --max-depth 3 --ignore-case --type file --type directory "$pattern" . 2>/dev/null
	else
		rg --files --hidden --glob '!.git/**' 2>/dev/null | rg -i "$rg_pattern"
	fi
}

printf '\n== Project instruction/config files ==\n'
list_project_instruction_files | sort | head -200 || true

printf '\n== TODO/FIXME/HACK markers ==\n'
rg -n --hidden \
	--glob '!.git/**' \
	--glob '!node_modules/**' \
	--glob '!dist/**' \
	--glob '!build/**' \
	--glob '!.venv/**' \
	--glob '!venv/**' \
	'TODO|FIXME|HACK|XXX' . 2>/dev/null | head -100 || true

printf '\n== Suggested next inspection commands ==\n'
printf '%s\n' \
  'Read AGENTS.md / README / CONTRIBUTING if present.' \
  'Inspect changed files from git diff --name-only.' \
  'Use rg or fd/fdfind for follow-up searches, per AGENTS.md.' \
  'Run the fastest available test/lint/build command only if it is already configured and non-destructive.'
