set dotenv-load

# WoW install root (the folder that contains _forever_). Override with WOW_DIR in the
# environment or in a .env file (gitignored). Linux has no standard location; the default
# is a Wine prefix at ~/Games/battlenet.
wow_dir := env("WOW_DIR", if os() == "windows" {
    "C:/Program Files (x86)/World of Warcraft"
} else if os() == "macos" {
    "/Applications/World of Warcraft"
} else {
    home_directory() / "Games/battlenet/drive_c/Program Files (x86)/World of Warcraft"
})
addons_dir := wow_dir / "_forever_/Interface/AddOns"

# run tools from mise.toml even if mise isn't activated in the shell
x := "mise exec --"
lua_files := "$(git ls-files --cached --others --exclude-standard '*.lua' ':!types/*' ':!scripts/*')"
api_docs := ".cache/wow-ui-source-forever/Interface/AddOns/Blizzard_APIDocumentationGenerated"

# list recipes
default:
    @just --list

# symlink every addon (dir containing <name>/<name>.toc) into the WoW AddOns folder
link: _check-addons-dir
    #!/usr/bin/env bash
    set -euo pipefail
    for toc in */*.toc; do
        name="$(dirname "$toc")"
        [ "$(basename "$toc" .toc)" = "$name" ] || continue
        target="{{addons_dir}}/$name"
        if [ -L "$target" ]; then
            echo "ok      $name"
        elif [ -e "$target" ]; then
            echo "SKIP    $name (exists and is not a symlink)" >&2
        else
            ln -s "$PWD/$name" "$target"
            echo "linked  $name"
        fi
    done

# remove symlinks that point back into this repo
unlink: _check-addons-dir
    #!/usr/bin/env bash
    set -euo pipefail
    for target in "{{addons_dir}}"/*; do
        [ -L "$target" ] || continue
        case "$(readlink "$target")" in
            "$PWD"/*) rm "$target"; echo "unlinked $(basename "$target")" ;;
        esac
    done

# show addons in the WoW folder that are linked from this repo
status: _check-addons-dir
    #!/usr/bin/env bash
    set -euo pipefail
    echo "AddOns: {{addons_dir}}"
    for target in "{{addons_dir}}"/*; do
        [ -L "$target" ] || continue
        dest="$(readlink "$target")"
        case "$dest" in "$PWD"/*) echo "  $(basename "$target") -> $dest" ;; esac
    done

[private]
_check-addons-dir:
    @[ -d "{{addons_dir}}" ] || { echo "AddOns folder not found: {{addons_dir}}" >&2; echo "Set WOW_DIR (env or .env) to the folder that contains _forever_." >&2; exit 1; }

# fetch/update Forever UI source + API docs and LuaLS annotations; install git hooks
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    {{x}} true  # make sure mise tools are installed
    {{x}} lefthook install
    fetch() { # url branch dir
        if [ -d "$3/.git" ]; then
            git -C "$3" fetch -q --depth 1 origin "$2" && git -C "$3" reset -q --hard FETCH_HEAD
        else
            git clone -q --depth 1 -b "$2" "$1" "$3"
        fi
        echo "$3: $(git -C "$3" log -1 --format='%cs %s')"
    }
    # Blizzard's own UI code + generated API docs for the Forever client (source of truth)
    src=.cache/wow-ui-source-forever
    if [ ! -d "$src/.git" ]; then
        git clone -q --depth 1 --filter=blob:none --sparse -b forever https://github.com/Gethe/wow-ui-source.git "$src"
        git -C "$src" sparse-checkout set --no-cone '/Interface/AddOns/'
    else
        git -C "$src" fetch -q --depth 1 origin forever && git -C "$src" reset -q --hard FETCH_HEAD
    fi
    echo "$src: $(git -C "$src" log -1 --format='%cs %s')"
    fetch https://github.com/Ketho/vscode-wow-api.git master .cache/vscode-wow-api
    fetch https://github.com/NumyAddon/FramexmlAnnotations.git forever .cache/framexml-forever

# syntax-check with Lua 5.1, check events/C_ APIs against Forever's docs, type-check with LuaLS
check: _ensure-setup
    #!/usr/bin/env bash
    set -euo pipefail
    for f in {{lua_files}}; do {{x}} luac -p "$f"; done
    echo "luac 5.1: ok"
    {{x}} lua scripts/check-api.lua "{{api_docs}}" {{lua_files}}
    out="$({ {{x}} lua-language-server --check . --checklevel=Warning 2>&1 || true; } | tr '\r' '\n' | sed 's/\x1b\[[0-9;]*m//g' | grep -v -e '^Initializing' -e '>>>>' -e '^ *$')"
    echo "$out"
    grep -q "no problems found" <<<"$out"

# run setup only if the cache is missing (just has no "is this up to date" check of its own)
[private]
_ensure-setup:
    @[ -d "{{api_docs}}" ] || {{just_executable()}} setup

# format all addon Lua with stylua
fmt:
    {{x}} stylua {{lua_files}}

# fail if anything isn't formatted
fmt-check:
    {{x}} stylua --check {{lua_files}}
