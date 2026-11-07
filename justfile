addons_dir := "/home/selkie/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"

# run tools from mise.toml even if mise isn't activated in the shell
x := "mise exec --"
lua_files := "$(git ls-files --cached --others --exclude-standard '*.lua' ':!types/*')"

# list recipes
default:
    @just --list

# symlink every addon (dir containing <name>/<name>.toc) into the WoW AddOns folder
link:
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
unlink:
    #!/usr/bin/env bash
    set -euo pipefail
    for target in "{{addons_dir}}"/*; do
        [ -L "$target" ] || continue
        case "$(readlink "$target")" in
            "$PWD"/*) rm "$target"; echo "unlinked $(basename "$target")" ;;
        esac
    done

# show addons in the WoW folder that are linked from this repo
status:
    @find "{{addons_dir}}" -maxdepth 1 -type l -lname "$PWD/*" -printf '%f -> %l\n'

# fetch/update WoW API annotations used by lua-language-server
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    {{x}} true  # make sure mise tools are installed
    fetch() { # url branch dir
        if [ -d "$3/.git" ]; then
            git -C "$3" fetch -q --depth 1 origin "$2" && git -C "$3" reset -q --hard FETCH_HEAD
        else
            git clone -q --depth 1 -b "$2" "$1" "$3"
        fi
        echo "$3: $(git -C "$3" log -1 --format='%cs %s')"
    }
    fetch https://github.com/Ketho/vscode-wow-api.git master .cache/vscode-wow-api
    fetch https://github.com/NumyAddon/FramexmlAnnotations.git forever .cache/framexml-forever

# syntax-check with Lua 5.1 and type-check against the WoW API
check:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -d .cache/vscode-wow-api ] || just setup
    for f in {{lua_files}}; do {{x}} luac -p "$f"; done
    echo "luac 5.1: ok"
    out="$({{x}} lua-language-server --check . --checklevel=Warning 2>&1 | tr '\r' '\n' | sed 's/\x1b\[[0-9;]*m//g' | grep -v -e '^Initializing' -e '>>>>' -e '^ *$')"
    echo "$out"
    grep -q "no problems found" <<<"$out"

# format all addon Lua with stylua
fmt:
    {{x}} stylua {{lua_files}}

# fail if anything isn't formatted
fmt-check:
    {{x}} stylua --check {{lua_files}}
