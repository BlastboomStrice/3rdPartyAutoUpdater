# 3rdPartyAutoUpdater
Auto updates programs from github, gitlab, etc. I tried it in Debian Testing (Trixie).

## Warning
This script contains dangerous commands, like `sudo rm -r`. Please be careful. Don't forget to add all the necessary info for each package in the .json file (it's important to not have empty items, that's why I name them "null"). I'm not responsible for any damage this script may cause.

## NixOS
After writing all this script, I realized that Nix package manager uses a similar (but probably much better) approach. Thus, I think it's better to use nix manager instead.

## HOW IT WORKS:
This script comes with a local .json file, that contains the essential info of the programs we need to install. The script iterates this info and serially checks if there is a new version, if yes it downloads it and the it installs it. Finally it clears the residual files and updates the .json file. I originally made this to auto-update apps that don't exist in my apt repos.

Currently updates:
1. SuperTuxKart
2. OpenRGB
3. Veloren
4. ABDownloadManager
5. Czkawka
6. Jellyfin-media-player
7. LRCGET
8. Ludusavi
9. OneTagger
10. Etcher
11. Rustic
12. SiteOne-Crawler
13. ytDownloader
14. Godot
15. Meshroom
16. Mindustry
17. DiscordChatExporter-Gui
18. Striling-PDF
19. Blender
20. Natron
21. PDFsamBasic
Happy updating!
