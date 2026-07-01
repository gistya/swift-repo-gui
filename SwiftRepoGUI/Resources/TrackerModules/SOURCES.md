# Tracker Module Sources

These tracker modules are bundled as soundtrack source material for SwiftBuilder.
SwiftBuilder discovers every `.mod`, `.xm`, `.it`, `.s3m`, and `.mptm` file in this bundle folder at runtime and randomly picks from that set when the soundtrack starts or changes moments.

AVFoundation does not natively decode tracker module formats, so playback currently uses SwiftBuilder's in-app tracker-style renderer seeded by the selected module file. A future libopenmpt-backed player can replace the renderer behind the same module discovery path.

Source URLs are copied from each file's macOS `Where from` metadata when available. Older files without that extended attribute use their known Mod Archive download URL.

| File | Format | Where From |
| --- | --- | --- |
| `10kdub.mod` | MOD | https://api.modarchive.org/downloads.php?moduleid=201827#10kdub.mod |
| `1kb.it` | IT | https://api.modarchive.org/downloads.php?moduleid=211479#1kb.it |
| `4_rndd!.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=172898#4_rndd!.xm |
| `8bit_castle.mod` | MOD | https://api.modarchive.org/downloads.php?moduleid=195782#8bit_castle.mod |
| `a_winter_kiss.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=174546#a_winter_kiss.xm |
| `aeolus.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=177398#aeolus.xm |
| `allsort.mod` | MOD | https://api.modarchive.org/downloads.php?moduleid=33325#allsort.mod |
| `bionic_girl.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=174416#bionic_girl.xm |
| `biotech.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=174348#biotech.xm |
| `bitshift.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=166135#bitshift.xm |
| `borneofunction.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=193717#borneofunction.xm |
| `brasstheme.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=212236#brasstheme.xm |
| `chip_overture.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=172185#chip_overture.xm |
| `dailyagony.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=169183#dailyagony.xm |
| `dancequeen.it` | IT | https://api.modarchive.org/downloads.php?moduleid=35956#dancequeen.it |
| `drozerix_-_bubble_machine.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=176020#drozerix_-_bubble_machine.xm |
| `drozerix_-_chica-pop!.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=189433#drozerix_-_chica-pop!.xm |
| `drozerix_-_computer_fuck!.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=175021#drozerix_-_computer_fuck!.xm |
| `drozerix_-_crush.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=179581#drozerix_-_crush.xm |
| `drozerix_-_digital_rendezvous.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=180821#drozerix_-_digital_rendezvous.xm |
| `drozerix_-_may_is_4_her.mod` | MOD | https://api.modarchive.org/downloads.php?moduleid=197296#drozerix_-_may_is_4_her.mod |
| `drozerix_-_mecanum_overdrive.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=175349#drozerix_-_mecanum_overdrive.xm |
| `drozerix_-_my_dearest.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=205731#drozerix_-_my_dearest.xm |
| `drozerix_-_neon_techno.mod` | MOD | https://api.modarchive.org/downloads.php?moduleid=178172#drozerix_-_neon_techno.mod |
| `drozerix_-_peachy_chip.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=191437#drozerix_-_peachy_chip.xm |
| `drozerix_-_playful_girl.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=185337#drozerix_-_playful_girl.xm |
| `drozerix_-_sleepy_snow.xm` | XM | https://api.modarchive.org/downloads.php?moduleid=196372#drozerix_-_sleepy_snow.xm |
| `drozerix_-_stardust_jam.mod` | MOD | https://api.modarchive.org/downloads.php?moduleid=201039#drozerix_-_stardust_jam.mod |
