#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
loader_dir="${1:-$HOME/.local/share/Steam/steamapps/common/Manor Lords/ManorLords/Binaries/Win64/ue4ss}"
mods="$loader_dir/Mods"
if pgrep -f '[M]anorLords-Win64-Shipping.exe' >/dev/null; then
    echo 'Close Manor Lords before installing.' >&2
    exit 1
fi
if [[ ! -f "$loader_dir/UE4SS.dll" || ! -d "$mods" ]]; then
    echo 'UE4SS was not found. Pass its folder as the first argument.' >&2
    exit 1
fi

# Stage the package before moving any installed mod.
backup="$(mktemp -d -- "$loader_dir/mod-pack-backup.XXXXXX")"
previous=()
rollback() {
    for name in "${previous[@]}"; do
        mv -- "$backup/$name" "$mods/$name"
    done
}
trap rollback EXIT
cp -R -- "$source_dir/ManorLordsModPack" "$backup/new"
for name in NPCPloughing2x NPCFarming4x TreeGrowth4x TreeGrowth10x Tariff5PastureBreeding Tariff2PastureBreeding YarnClothes4x Clothes4x BarleyMaltAle Planks15RoyalTax500 ManorLordsModPack; do
    if [[ -e "$mods/$name" || -L "$mods/$name" ]]; then
        mv -- "$mods/$name" "$backup/$name"
        previous+=("$name")
    fi
done
mv -T -- "$backup/new" "$mods/ManorLordsModPack"
trap - EXIT
echo "Installed ManorLordsModPack. Previous mod folders are backed up in $backup."
