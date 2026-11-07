addons_dir := "/home/selkie/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"

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
