#!/usr/bin/env bash
# generate.sh
#
# Selects, renders, and installs GitHub workflow templates into the current
# project. Templates are read from the ghwt repo, resolved relative to this
# script — call it from any project directory via the ghwt symlink.
#
# Usage:
#   ghwt                                  # fully interactive
#   ghwt ci release                       # pre-select workflow categories;
#                                         # still prompts for language, pm,
#                                         # and placeholders
#
# Config file: .ghwt (in PWD)
#   Persists previously supplied placeholder values. Stored values are
#   offered as defaults at each prompt.
#
# Template repo structure expected:
#   <language>/
#     <pm>/
#       ci/
#         default.yml
#       gh-pages/
#         <framework>.yml
#       release/
#         <target>.yml
#   generic/
#     dependabot/
#       default.yml       ← @@PACKAGE_MANAGER@@ resolved from pm selection
#     mirror/
#       codeberg.yml
#
# Output:
#   .github/workflows/<name>.yml    — ci, gh-pages variants, release variants, mirror
#   .github/dependabot.yml          — dependabot (special case)
#
# Placeholder syntax: @@VAR_NAME@@ (e.g. @@GITHUB_USER@@)
# @@PACKAGE_MANAGER@@ is injected automatically from the pm selection.

set -euo pipefail

CONFIG_FILE=".ghwt"
# ANSI color codes — disabled automatically when stderr is not a terminal
if [ -t 2 ]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' RED='' RESET=''
fi
TEMPLATES_DIR="$(cd "$(dirname "$0")" && pwd)/src"

[ ! -d "$TEMPLATES_DIR" ] && echo "Error: src/ directory not found in $(dirname "$0")" >&2 && exit 1

GITHUB_DIR=".github"
GITHUB_WORKFLOWS_DIR="$GITHUB_DIR/workflows"

# Run installer if bin/ghwt symlink does not exist yet
. "$(dirname "$0")/install.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

config_get() {
    # config_get KEY VAR — stores value (or empty string) in VAR
    local key="$1" var="$2" value=""
    if [ -f "$CONFIG_FILE" ]; then
        value=$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)
    fi
    eval "${var}=\${value}"
}

config_set() {
    # config_set KEY VALUE — upserts a key in the config file
    local key="$1" value="$2"
    local exists=0
    [ -f "$CONFIG_FILE" ] && grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null && exists=1 || true
    if [ $exists -eq 1 ]; then
        local tmp
        tmp=$(mktemp)
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp" || true
        echo "${key}=${value}" >> "$tmp"
        mv "$tmp" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

prompt() {
    # prompt KEY LABEL VAR — reads input with stored default offered;
    # saves to config and stores result in VAR
    local key="$1" label="$2" var="$3" default="" _prompt_val=""
    config_get "$key" default
    if [ -n "$default" ]; then
        printf '%s [%s]: ' "$label" "$default" >&2
    else
        printf '%s: ' "$label" >&2
    fi
    read -r _prompt_val </dev/tty
    [ -z "$_prompt_val" ] && _prompt_val="$default"
    config_set "$key" "$_prompt_val"
    eval "${var}=\${_prompt_val}"
}

pick_one() {
    # pick_one LABEL VAR item1 item2 ...
    # Single-choice prompt; resolves silently if only one item.
    # Stores chosen item in VAR.
    local label="$1" var="$2"; shift 2
    local items=("$@")
    if [ ${#items[@]} -eq 1 ]; then
        eval "${var}=\${items[0]}"
        return
    fi
    echo "" >&2
    local i=1
    for item in "${items[@]}"; do
        printf '  %d) %s\n' "$i" "$item" >&2
        i=$((i + 1))
    done
    echo "" >&2
    printf '%s: ' "$label" >&2
    local choice
    read -r choice </dev/tty
    if ! printf '%s' "$choice" | grep -qE '^[0-9]+$' || \
       [ "$choice" -lt 1 ] || [ "$choice" -gt ${#items[@]} ]; then
        printf "${RED}Error: invalid selection '%s'.${RESET}\n" "$choice" >&2
        exit 1
    fi
    eval "${var}=\${items[\$((choice - 1))]}"
}

pick_many() {
    # pick_many LABEL ARRAY_VAR item1 item2 ...
    # Multi-choice prompt; stores chosen items in ARRAY_VAR.
    # Enter to select all; comma-separated numbers to select a subset.
    local label="$1" var="$2"; shift 2
    local items=("$@")
    echo "" >&2
    local i=1
    for item in "${items[@]}"; do
        printf '  %d) %s\n' "$i" "$item" >&2
        i=$((i + 1))
    done
    echo "" >&2
    printf '%s (comma-separated numbers, enter to select all): ' "$label" >&2
    local selections
    read -r selections </dev/tty
    eval "${var}=()"
    if [ -z "$selections" ]; then
        # Empty input — select all
        eval "${var}=(\"\${items[@]}\")"
        return
    fi
    # Replace commas with spaces for iteration
    selections="${selections//,/ }"
    for num in $selections; do
        if ! printf '%s' "$num" | grep -qE '^[0-9]+$' || \
           [ "$num" -lt 1 ] || [ "$num" -gt ${#items[@]} ]; then
            printf "${RED}Error: invalid selection '%s'.${RESET}\n" "$num" >&2
            exit 1
        fi
        eval "${var}+=(\"\${items[\$((num - 1))]}\")"
    done
}

# ---------------------------------------------------------------------------
# Step 1 — Select language
# ---------------------------------------------------------------------------

languages=()
for dir in "$TEMPLATES_DIR"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    [ "$name" = "generic" ] && continue
    languages+=("$name")
done

[ ${#languages[@]} -eq 0 ] && printf "${RED}Error: no languages found in %s${RESET}\n" "$TEMPLATES_DIR" >&2 && exit 1

echo "" >&2
printf "${BOLD}Step 1 — Language${RESET}\n" >&2
pick_one "Select language" selected_language "${languages[@]}"
printf "  ${GREEN}→ %s${RESET}\n" "$selected_language" >&2

# ---------------------------------------------------------------------------
# Step 2 — Select package manager
# ---------------------------------------------------------------------------

pkg_managers=()
for dir in "$TEMPLATES_DIR/$selected_language"/*/; do
    [ -d "$dir" ] || continue
    pkg_managers+=("$(basename "$dir")")
done

[ ${#pkg_managers[@]} -eq 0 ] && printf "${RED}Error: no package managers found for '%s'.${RESET}\n" "$selected_language" >&2 && exit 1

echo "" >&2
printf "${BOLD}Step 2 — Package manager${RESET}\n" >&2
pick_one "Select package manager" selected_pm "${pkg_managers[@]}"
printf "  ${GREEN}→ %s${RESET}\n" "$selected_pm" >&2

lang_pm_dir="$TEMPLATES_DIR/$selected_language/$selected_pm"

# ---------------------------------------------------------------------------
# Step 3 — Select workflows
# ---------------------------------------------------------------------------

lang_workflows=()
for dir in "$lang_pm_dir"/*/; do
    [ -d "$dir" ] || continue
    lang_workflows+=("$(basename "$dir")")
done

generic_workflows=()
for dir in "$TEMPLATES_DIR/generic"/*/; do
    [ -d "$dir" ] || continue
    generic_workflows+=("$(basename "$dir")")
done

all_workflows=("${lang_workflows[@]+"${lang_workflows[@]}"}" "${generic_workflows[@]+"${generic_workflows[@]}"}")

[ ${#all_workflows[@]} -eq 0 ] && printf "${RED}Error: no workflows found.${RESET}\n" >&2 && exit 1

echo "" >&2
printf "${BOLD}Step 3 — Workflows${RESET}\n" >&2

if [ $# -gt 0 ]; then
    selected_workflows=("$@")
    for wf in "${selected_workflows[@]}"; do
        found=0
        for avail in "${all_workflows[@]}"; do
            [ "$wf" = "$avail" ] && found=1 && break
        done
        if [ $found -eq 0 ]; then
            printf "${RED}Error: unknown workflow '%s'. Available: %s${RESET}\n" "$wf" "${all_workflows[*]}" >&2
            exit 1
        fi
    done
else
    pick_many "Select workflows" selected_workflows "${all_workflows[@]}"
fi

[ ${#selected_workflows[@]} -eq 0 ] && printf "${YELLOW}No workflows selected. Exiting.${RESET}\n" >&2 && exit 0

printf "  ${GREEN}→ %s${RESET}\n" "${selected_workflows[*]}" >&2

# ---------------------------------------------------------------------------
# Step 4 — Resolve template paths
#
# For each selected workflow category:
#   - Look in <lang>/<pm>/<category>/ first, then generic/<category>/
#   - Single .yml → resolved automatically
#   - Multiple .yml → prompt user to pick one
#   - Output filename derived from file stem; "default" → category name
#   - dependabot → .github/dependabot.yml (special case)
#   - all others  → .github/workflows/<name>.yml
# ---------------------------------------------------------------------------

resolved=()  # entries: "template_path|output_path"

for wf in "${selected_workflows[@]}"; do
    lang_candidate="$lang_pm_dir/$wf"
    generic_candidate="$TEMPLATES_DIR/generic/$wf"

    if [ -d "$lang_candidate" ]; then
        src_dir="$lang_candidate"
    elif [ -d "$generic_candidate" ]; then
        src_dir="$generic_candidate"
    else
        printf "${YELLOW}Warning: no directory found for workflow '%s'. Skipping.${RESET}\n" "$wf" >&2
        continue
    fi

    yml_files=()
    for f in "$src_dir"/*.yml; do
        [ -f "$f" ] && yml_files+=("$f")
    done

    if [ ${#yml_files[@]} -eq 0 ]; then
        printf "${YELLOW}Warning: no .yml files in %s. Skipping.${RESET}\n" "$src_dir" >&2
        continue
    fi

    if [ ${#yml_files[@]} -eq 1 ]; then
        template_path="${yml_files[0]}"
    else
        variant_names=()
        for f in "${yml_files[@]}"; do
            variant_names+=("$(basename "$f" .yml)")
        done
        echo "" >&2
        echo "Multiple variants available for '$wf':" >&2
        pick_one "Select variant" choice "${variant_names[@]}"
        template_path="$src_dir/${choice}.yml"
    fi

    # Output filename always derived from the category directory name
    out_name="$wf"

    if [ "$wf" = "dependabot" ]; then
        output_path="$GITHUB_DIR/dependabot.yml"
    else
        output_path="$GITHUB_WORKFLOWS_DIR/${out_name}.yml"
    fi

    resolved+=("${template_path}|${output_path}")
done

[ ${#resolved[@]} -eq 0 ] && printf "${YELLOW}No templates resolved. Exiting.${RESET}\n" >&2 && exit 0

# ---------------------------------------------------------------------------
# Step 5 — Collect placeholder values
#
# @@PACKAGE_MANAGER@@ is injected automatically from the pm selection.
# All other @@PLACEHOLDERS@@ are discovered across resolved templates
# and prompted once, in order of first appearance.
# ---------------------------------------------------------------------------

placeholders=()
for entry in "${resolved[@]}"; do
    template_path="${entry%%|*}"
    while IFS= read -r ph; do
        [ "$ph" = "@@PACKAGE_MANAGER@@" ] && continue
        already=0
        for existing in "${placeholders[@]+"${placeholders[@]}"}"; do
            [ "$existing" = "$ph" ] && already=1 && break
        done
        [ $already -eq 0 ] && placeholders+=("$ph")
    done < <(grep -o '@@[A-Z_]*@@' "$template_path" 2>/dev/null | sort -u || true)
done

# Parallel arrays — bash 3.2 compatible (no associative arrays)
placeholder_keys=("PACKAGE_MANAGER")
placeholder_vals=("$selected_pm")

if [ ${#placeholders[@]} -gt 0 ]; then
    echo "" >&2
    printf "${BOLD}Step 4 — Project settings${RESET}\n" >&2
    for ph in "${placeholders[@]}"; do
        # Seed NODE_VERSION default if not already set
        if [ "${ph//@@/}" = "NODE_VERSION" ]; then
            _existing_node=""
            config_get "NODE_VERSION" _existing_node
            [ -z "$_existing_node" ] && config_set "NODE_VERSION" "22"
        fi
        key="${ph//@@/}"
        # Derive human-readable label: strip @@, lowercase, replace _ with space
        label=$(printf '%s' "$key" | tr '[:upper:]_' '[:lower:] ')
        # For Codeberg keys, seed default from collected GitHub counterpart if unset
        if [ "$key" = "CODEBERG_USER" ]; then
            _existing=""
            config_get "CODEBERG_USER" _existing
            if [ -z "$_existing" ]; then
                _gh_user=""
                config_get "GITHUB_USER" _gh_user
                [ -n "$_gh_user" ] && config_set "CODEBERG_USER" "$_gh_user"
            fi
        fi
        if [ "$key" = "CODEBERG_REPO" ]; then
            _existing=""
            config_get "CODEBERG_REPO" _existing
            if [ -z "$_existing" ]; then
                _gh_repo=""
                config_get "GITHUB_REPO" _gh_repo
                [ -n "$_gh_repo" ] && config_set "CODEBERG_REPO" "$_gh_repo"
            fi
        fi
        if [ "$key" = "PYPI_PACKAGE" ]; then
            _existing=""
            config_get "PYPI_PACKAGE" _existing
            if [ -z "$_existing" ]; then
                _gh_repo=""
                config_get "GITHUB_REPO" _gh_repo
                [ -n "$_gh_repo" ] && config_set "PYPI_PACKAGE" "$_gh_repo"
            fi
        fi
        prompt "$key" "$label" value
        placeholder_keys+=("$key")
        placeholder_vals+=("$value")
    done
fi

# ---------------------------------------------------------------------------
# Step 6 — Render and install
# ---------------------------------------------------------------------------

echo "" >&2
printf "${BOLD}Installing${RESET}\n" >&2
echo "----------" >&2

mkdir -p "$GITHUB_WORKFLOWS_DIR"

# Ask once if any output files already exist
overwrite_all=0
for entry in "${resolved[@]}"; do
    output_path="${entry##*|}"
    if [ -f "$output_path" ]; then
        printf "One or more output files already exist. Overwrite all? [y/N] " >&2
        read -r confirm </dev/tty
        case "$confirm" in
            [yY]|[yY][eE][sS]) overwrite_all=1 ;;
            *) overwrite_all=0 ;;
        esac
        break
    fi
done

for entry in "${resolved[@]}"; do
    template_path="${entry%%|*}"
    output_path="${entry##*|}"

    content=$(cat "$template_path")

    i=0
    while [ $i -lt ${#placeholder_keys[@]} ]; do
        content="${content//@@${placeholder_keys[$i]}@@/${placeholder_vals[$i]}}"
        i=$((i + 1))
    done

    remaining=$(printf '%s' "$content" | grep -o '@@[A-Z_]*@@' | sort -u || true)
    [ -n "$remaining" ] && printf "${YELLOW}Warning: unreplaced placeholders in %s: %s${RESET}\n" "$output_path" "$remaining" >&2

    if [ -f "$output_path" ] && [ $overwrite_all -eq 0 ]; then
        printf "  ${YELLOW}Skipping %s.${RESET}\n" "$output_path" >&2
        continue
    fi

    mkdir -p "$(dirname "$output_path")"
    printf '%s\n' "$content" > "$output_path"
    printf "  ${GREEN}✓ %s${RESET}\n" "$output_path" >&2
done

echo "" >&2
echo "Done." >&2