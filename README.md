# 3rdPartyAutoUpdater
Auto updates programs from github, gitlab, etc.

## HOW IT WORKS:
This script comes with a local .json file, that contains the essential info of the programs we need to install. The script iterates this info and serially checks if there is a new version, if yes it downloads it and the it installs it. Finally it clears the residual files and updates the .json file. I originally made this to auto-update apps that don't exist in my apt repos.

Happy updating!
