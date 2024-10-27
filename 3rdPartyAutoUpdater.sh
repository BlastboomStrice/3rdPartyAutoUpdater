#!/bin/bash

: <<'END_COMMENT'
#HOW IT WORKS:
This script comes with a local .json file, that contains the essential
info of the programs we need to install. The script iterates this info
and serially checks if there is a new version, if yes it downloads it
and the it installs it. Finally it clears the residual files and updates
the .json file. Happy updating! I made it to auto-update apps that don't
exist in my apt repos.
END_COMMENT

shopt -s lastpipe	#makes the last part of the pipeline run in the current environment (not sure exactly if I need it)

#GLOBAL-VARIABLES
dpath="/tmp/3rdPartyAutoUpdater/"	#path to download and extract stuff

programName="null"	#name of program
programID="null"	#ID or part of url to match with site api
url="null"			#url of old version of program
newUrl="null"		#url of new version of program (gets written to $url after the update)	#not in .json
fetcherType="null"	#type of fetcher to use (Github, etc.)
binaryType="null"	#type of binary to pick from the site #this is what file the jq will search for
fileName="null"		#the filename of the downloaded program
fileExt="null"		#the extension of the file
programExe="null"	#the (relative path to) file in the program folder that launches the program
declare -i programIndex=0	#the index of each object in the .json array	#not in .json

#INITIALIZE-LOG
initialize_log(){
	echo "Please put in your password to start"
	sudo echo "Thank you, lets goo"	#gets sudo permission for our script so as not to bother the user later when we will use sudo
	timeStamp=$(date +'%F_%H:%M:%S')	#current timestamp in yyyy-mm-dd_hh:mm:ss format
	echo "Current timestamp: $timeStamp"
	cat <<< "$(jq --arg timeStamp "$timeStamp" '(.[] | select (.programName == "null")).timestamp |= $timeStamp' 3rdPartyAutoUpdaterConf.json)" > 3rdPartyAutoUpdaterConf.json #updates timestamp in Conf file
}

#FETCHERS (some repos needs custom fetchers because they don't follow the standard)
github_fetcher(){
	curl -s "https://api.github.com/repos/$programID/releases/latest" | jq --arg binaryType "$binaryType" -r '(.assets[] | select(.name)).browser_download_url' | grep -E "$binaryType" | read -r newUrl	#finds the url for the file and writes it to $newUrl

	#the contains() doesn't use regex, so I had to give it up, as one app needed to grep x64.*deb
	#curl -s https://api.github.com/repos/$programID/releases/latest | jq --arg binaryType "$binaryType" -r '(.assets[] | select(.name | contains($binaryType))).browser_download_url' | read -r newUrl	#finds the url for the file and writes it to $newUrl
}

gitlab_openrgb_fetcher(){
	curl -sL "https://gitlab.com/api/v4/projects/$programID/releases/permalink/latest" | jq --arg binaryType "$binaryType" -r '.description' | grep -oE "$binaryType.*\)" | cut -f2 -d"(" | cut -f1 -d")" | read -r newUrl
	#We want the link between here:
	#[Debian Bookworm amd64](https://openrgb.org/releases/release_0.9/openrgb_0.9_amd64_bookworm_b5f46e3.deb)\n\n[Debian Bookworm i386]
	#Prints text without escape sequences, grabs the line with the link I want, and cuts anything after "(" and before ")"

	#Alternative:
	#curl -sL https://gitlab.com/api/v4/projects/10582521/releases/permalink/latest | jq '.description' release.json | sed -e 's/.*Debian Bookworm amd64\](\(.*\))\\n\\n\[Debian Bookworm i386.*/\1/' | read url
	#Filters out everything but the link I want. This might break if they move the binaries out of the description or if they change the characters around the link (in our case "Debian Bookworm amd64](" and ")\n\n[Debian Bookworm i386"
}

gitlab_veloren_fetcher(){
	curl -sL "https://gitlab.com/api/v4/projects/$programID/releases/permalink/latest" | jq --arg binaryType "$binaryType" -r '(.assets.links[] | select(.name==$binaryType)).direct_asset_url' | read -r newUrl
}

site(){
	echo "If there are any %xx escape characters in the link, the installation will fail"
	#If there are any %XX escape characters in the link, the installation will fail
	#We need to implement a Python module urllib.unquote(filename) that will replace %xx escapes by their single-character equivalent.
	mech-dump --links --absolute --agent-alias='Linux Mozilla' "$programID" | grep -m1 "$binaryType" | read -r newUrl
}

: <<'END_COMMENT'
#Decided to use flatpak for Eclipse. The site only provides the installer, not the binary...
#site_eclipse(){
#	mech-dump --links --absolute --agent-alias='Linux Mozilla' "$programID" | grep -m1 "$binaryType" | read -r newUrl
#	newUrl+="&r=1" #adds the mirror redirect to newUrl string to download the file
#}

json object:
	{
		"programName": "EclipseIDE",
		"programID": "https://www.eclipse.org/downloads/packages/installer",
		"fetcherType": "site_eclipse",
		"binaryType": "linux64.tar.gz",
		"url": "null",
		"fileName": "null",
		"fileExt": "tar",
		"programExe": "null"
	}
END_COMMENT

#FETCHER Picks fetcher
fetcher(){
	case $fetcherType in
	github)
		github_fetcher
		;;
	gitlab_veloren)
		gitlab_veloren_fetcher
		;;
	gitlab_openrgb)
		gitlab_openrgb_fetcher
		;;
	site)
		site
		;;
	*)
		echo "This type of fetcher does not exist. Implement it or check for typo in fetcherType item in json object of $programName"
		exit	#exits program, there is a failure
		;;
	esac

	cat <<< "$(jq --arg programName "$programName" --arg newUrl "$newUrl" -r '(.[] | select (.programName==$programName)).url |= $newUrl' 3rdPartyAutoUpdaterConf.json)" > 3rdPartyAutoUpdaterConf.json	#updates url of program in Conf file

	echo "THIS IS THE URL: $newUrl"	#testing stuff here
}

#DOWNLOADER
downloader(){
	#create temp dir
	mkdir -p "$dpath" #creates temporary directory to extract files
	#download
	wget -N "$newUrl" -P "$dpath" #donwloads the file
	fileName=$(basename "$newUrl") #creates the filename by keeping only anything after the last "/" in the url
	cat <<< "$(jq --arg programName "$programName" --arg fileName "$fileName" -r '(.[] | select (.programName==$programName)).fileName |= $fileName' 3rdPartyAutoUpdaterConf.json)" > 3rdPartyAutoUpdaterConf.json	#updates filename of program in Conf file
	echo "THIS IS THE FILENAME: $fileName" #testing stuff here
}

#NON-DEB-INSTALLER #might need different name if we start fetching AppImages
non_deb_installer(){
	echo "Clearing $programName Dir"
	sudo rm -r "/opt/$programName/"	#it used to be sudo rm -r "/opt/$programName/" but that was a bit more dangerous
	#cleans old installation files

	if [ "$fileExt" != "null" ]; then	#as long as the program is not an uncompressed file, do
		echo "Deleting downloaded file"
		rm -f "$dpath$fileName"
		#deletes downloaded file after extraction
	fi

	echo "Creating $programName Dir"
	sudo mkdir "/opt/$programName/"
	#creates new programDir

	echo "Moving extracted files to $programName Dir"
	sudo mv "$dpath"* "/opt/$programName/"
	#moves files to /opt/programDir/

	if [ "$programExe" != "null" ]; then	#as long as the program has an executable file, do
		if [ "$fileExt" = "jar" ]; then	#in case of jar filExt, we need to add the .jar suffix to our symlink name
			echo "Removing old $programName.$fileExt symlink"
			sudo rm -f "/usr/bin/$programName.$fileExt"	#removes old symlink
			echo "Creating new $programName.$fileExt symlink"
			sudo ln -s "/opt/$programName/"$programExe "/usr/bin/$programName.$fileExt"
		fi
		echo "Removing old $programName symlink"
		sudo rm -f "/usr/bin/$programName"	#removes old symlink
		echo "Creating new $programName symlink"
		sudo ln -s "/opt/$programName/"$programExe "/usr/bin/$programName"	#custom for each program	#quotes are missing on $programExe ON PURPOSE
		#creates symlink to bin #$programExe doesn't have quotes because sometimes it starts with "*/" to go inside the 1st single dir
		#note: Godot programExe is "*", because it is a single file that changes name
	fi
}

#EXTRACTING-INSTALLING
installer(){
	echo "Installing..."

	#obsolete:
	#fileExt=$(echo "$fileName" | grep -o ".\{4\}$")	#grabs the extension of the file (we mostly care if it is .deb or .zip)
	#echo "$fileExt file"

	case $fileExt in
	deb)
		echo "Performing apt install"
		echo "It should work as long as your repo has the necessary dependencies online!"
		sudo apt-get -y install "$dpath$fileName" #-y auto-install dependencies
		#echo "Deleting downloaded file"
		#rm -f "$dpath$fileName"	#deletes downloaded file after extraction
		;;
	zip)
		unzip "$dpath$fileName" -d "$dpath"
		non_deb_installer
		;;
	tar)	#tar.* files
		tar -xvf "$dpath$fileName" -C "$dpath"	#extracts tar
		non_deb_installer
		;;
	jar)
		non_deb_installer
		;;
	null)
		non_deb_installer
		;;
	*)
		echo "This type of file extention does not exist. Implement it or check for typo in fileExt item in json object of $programName"
		exit	#exits program, there is a failure
		;;
	esac

	echo "Cleaning $dpath Dir"
	rm -rf "$dpath" #removes dir where packages where downloaded
}

#VERSION-CHECK
version_check_and_update(){
	fetcher	#fetches the latest url of the program
if [ "$url" = "$newUrl" ]; then
	echo "No new version"
else
	echo "New version found. Updating..."
	downloader
	installer
fi
}

#START
initialize_log

#RUN MAIN PROCESS

#Iterates through the .json file to fetch data (not very sure about its robustness)
cat 3rdPartyAutoUpdaterConf.json | jq -c '.[]' | cat -n | while read -r i obj; do
  if [ $i -gt 1 ]; then	#skips the 0th item, because it is the example object
	programIndex=$((i - 1))
    echo "$programIndex"

	#WRITES all the necessary variables
	programName=$(jq --argjson programIndex $programIndex -r '.[$programIndex].programName' 3rdPartyAutoUpdaterConf.json)	#gets the programName from .json and removes the "". The argjson parses the programIndex as an int instead of a string
	programID=$(jq --argjson programIndex $programIndex -r '.[$programIndex].programID' 3rdPartyAutoUpdaterConf.json)	#gets the programID from .json and removes the "". The argjson parses the programIndex as an int instead of a string
	url=$(jq --argjson programIndex $programIndex -r '.[$programIndex].url' 3rdPartyAutoUpdaterConf.json)	#gets the url from .json and removes the "". The argjson parses the programIndex as an int instead of a string
	fetcherType=$(jq --argjson programIndex $programIndex -r '.[$programIndex].fetcherType' 3rdPartyAutoUpdaterConf.json)	#gets the fetcherType from .json and removes the "". The argjson parses the programIndex as an int instead of a string
	binaryType=$(jq --argjson programIndex $programIndex -r '.[$programIndex].binaryType' 3rdPartyAutoUpdaterConf.json)	#gets the binaryType from .json and removes the "". The argjson parses the programIndex as an int instead of a string
	fileExt=$(jq --argjson programIndex $programIndex -r '.[$programIndex].fileExt' 3rdPartyAutoUpdaterConf.json)	#gets the  fileExt from .json and removes the "". The argjson parses the programIndex as an int instead of a string
	programExe=$(jq --argjson programIndex $programIndex -r '.[$programIndex].programExe' 3rdPartyAutoUpdaterConf.json)	#gets the  (relative path to)  programExe from .json and removes the "". The argjson parses the programIndex as an int instead of a string

	#RUNS the functions
	version_check_and_update
	
	#FLUSHES the variables (except for the programIndex)
	programName="null"	#name of program
	programID="null"		#ID or part of url to match with site api	
	url="null"			#url of old version of program
	newUrl="null"			#url of new version of program (gets written to $url after the update)
	fetcherType="null"	#type of fetcher to use (Github, etc.)
	binaryType="null"		#type of binary to pick from the site #this is what file the jq will search for
	fileName="null"		#the filename of the downloaded program
	fileExt="null"		#the extension of the file
	programExe="null"		#the (relative path to) file in the program folder that launches the program, keep "null" if there is none
  fi
done

#END
echo "FINISHED"

#I should probably use NixOS or at least Nix package manager instead of inveting the wheel

#LRCGET fails to be installed on debian testing on 2024-27-10 due to unmet dependencies.. "Some packages could not be installed."

#Keyviz fetches the non-alpha version that doesn't have the appropriate file. I remove it from the .json
#I'm commenting the json object here:
: <<'END_COMMENT'
{
    "programName": "Keyviz",
    "programID": "mulaRahul/keyviz",
    "fetcherType": "github",
    "binaryType": "linux.zip",
    "url": "null",
    "fileName": "null",
    "fileExt": "zip",
    "programExe": "keyviz"
  },
END_COMMENT

#dell-powermanager has a %xx escape characters issue. I remove it from the .json
#I'm commenting the json object here:
: <<'END_COMMENT'
  {
    "programName": "Dell-powermanager",
    "programID": "alexVinarskis/dell-powermanager",
    "fetcherType": "github",
    "binaryType": "amd64.deb",
    "url": "null",
    "fileName": "null",
    "fileExt": "deb",
    "programExe": "null"
  },
END_COMMENT
