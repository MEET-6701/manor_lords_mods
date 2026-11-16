# Manor Lords Mod Pack

One UE4SS mod for the Steam installation on CachyOS.

| Feature | Setting |
| --- | --- |
| Manual ploughing and sowing | 4× NPC animation rate |
| Tree growth | 10× multiplier |
| Foreign imports | 2 regional wealth per unit in tariffs |
| Pasture breeding | One lamb or calf per eligible adult pair of the same species every 12 in-game months, subject to pasture capacity |
| Clothes | 1 linen or 1 yarn → 4 clothes |
| Malt and ale | 1 barley → 4 malt, 1 malt → 4 ale |
| Planks | 1 timber → 15 planks |
| Annual royal tax | Capped at 500 treasury on supported game build 26185246 |

With Manor Lords closed, run `bash install.sh` from this directory. For a
different Steam library, pass the path to its `ue4ss` folder as an argument.
The installer moves the individual mods to a backup folder outside `Mods`
to prevent them from running twice. It prints the backup location.

Keep the existing Steam launch option for UE4SS. Check `ue4ss/UE4SS.log`
after loading a settlement. The royal tax DLL checks the executable before
applying the cap and logs a failure if the build is unsupported. The
combined package still needs an in-game check for gameplay effects.

To roll back, close the game, move `Mods/ManorLordsModPack` out of `Mods`,
and restore the previous mod folders from the backup.
