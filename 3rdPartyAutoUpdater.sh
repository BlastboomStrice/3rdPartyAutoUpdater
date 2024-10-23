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
programID="null"		#ID or part of url to match with site api	
url="null"			#url of old version of program
newUrl="null"			#url of new version of program (gets written to $url after the update)
fetcherType="null"	#type of fetcher to use (Github, etc.)
binaryType="null"		#type of binary to pick from the site #this is what file the jq will search for
fileName="null"		#the filename of the downloaded program
fileExt="null"		#the extension of the file
programExe="null"		#the (relative path to) file in the program folder that launches the program
declare -i programIndex=0	#the index of each object in the .json array

#INITIALIZE-LOG
initialize_log(){
	timeStamp=$(date +'%F_%H:%M:%S')	#current timestamp in yyyy-mm-dd_hh:mm:ss format
	echo "Current timestamp: $timeStamp"
	cat <<< $(jq --arg timeStamp "$timeStamp" '(.[] | select (.programName == "null")).timestamp |= $timeStamp' 3rdPartyAutoUpdaterConf.json) > 3rdPartyAutoUpdaterConf.json #updates timestamp in Conf file
}

#FETCHERS (some repos needs custom fetchers because they don't follow the standard)
github_fetcher(){
	curl -s https://api.github.com/repos/$programID/releases/latest | jq --arg binaryType "$binaryType" -r '(.assets[] | select(.name | contains($binaryType))).browser_download_url' | read newUrl	#finds the url for the file and writes it to $newUrl
}

gitlab_openrgb_fetcher(){
	curl -sL https://gitlab.com/api/v4/projects/$programID/releases/permalink/latest | jq --arg binaryType "$binaryType" -r '.description' | grep -oE "$binaryType.*\)" | cut -f2 -d"(" | cut -f1 -d")" | read newUrl
	#We want the link between here:
	#[Debian Bookworm amd64](https://openrgb.org/releases/release_0.9/openrgb_0.9_amd64_bookworm_b5f46e3.deb)\n\n[Debian Bookworm i386]
	#Prints text without escape sequences, grabs the line with the link I want, and cuts anything after "(" and before ")"

	#Alternative:
	#curl -sL https://gitlab.com/api/v4/projects/10582521/releases/permalink/latest | jq '.description' release.json | sed -e 's/.*Debian Bookworm amd64\](\(.*\))\\n\\n\[Debian Bookworm i386.*/\1/' | read url
	#Filters out everything but the link I want. This might break if they move the binaries out of the description or if they change the characters around the link (in our case "Debian Bookworm amd64](" and ")\n\n[Debian Bookworm i386"
}

gitlab_veloren_fetcher(){
	curl -sL https://gitlab.com/api/v4/projects/$programID/releases/v0.15.0 | jq --arg binaryType "$binaryType" -r '(.assets.links[] | select(.name==$binaryType)).direct_asset_url' | read newUrl
}

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
	*)
		echo "This type of fetcher does not exist. Implement it or check for typo in 5th arg in version_check_and_update() of $2"
		exit	#exits program, there is a failure
		;;
	esac

	cat <<< $(jq --arg programName "$programName" --arg newUrl "$newUrl" -r '(.[] | select (.programName==$programName)).url |= $newUrl' 3rdPartyAutoUpdaterConf.json) > 3rdPartyAutoUpdaterConf.json	#updates url of program in Conf file

	echo "THIS IS THE URL: $newUrl"	#testing stuff here
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

#DOWNLOADER
downloader(){
	#create temp dir
	mkdir -p "$dpath" #creates temporary directory to extract files
	#download
	wget -N $newUrl -P "$dpath" #donwloads the file
	fileName=$(basename "$newUrl") #creates the filename by keeping only anything after the last "/" in the url
	cat <<< $(jq --arg programName "$programName" --arg fileName "$fileName" -r '(.[] | select (.programName==$programName)).fileName |= $fileName' 3rdPartyAutoUpdaterConf.json) > 3rdPartyAutoUpdaterConf.json	#updates filename of program in Conf file
	echo "THIS IS THE FILENAME: $fileName" #testing stuff here
}

#EXTRACTING-INSTALLING
installer(){
	echo "Installing..."
	
	fileExt=$(echo "$fileName" | grep -o ".\{4\}$")	#grabs the extension of the file (we mostly care if it is .deb or .zip)
	echo "$fileExt file"

	if [ "$fileExt" = ".deb" ]; then
		echo "Performing apt install"
		sudo apt install "$dpath$fileName"
		echo "Deleting downloaded file"
		rm -f "$dpath$fileName"	#deletes downloaded file after extraction
	else	#we break the if, because the steps after instruction are the same for the rest of the conditions
		if [ "$fileExt" = ".zip" ]; then
			unzip "$dpath$fileName" -d "$dpath"
		else	#it's gonna be a tar.* file
			tar -xvf "$dpath$fileName" -C "$dpath"	#extracts tar
		fi
		
		echo "Clearing $programName Dir"
		sudo rm -rf "/opt/$programName/"
		#cleans old installation files
		
		echo "Deleting downloaded file"
		rm -f "$dpath$fileName"
		#deletes downloaded file after extraction
		
		echo "Creating $programName Dir"
		sudo mkdir "/opt/$programName/"
		#creates new programDir
		
		echo "Moving extracted files to $programName Dir"
		sudo mv "$dpath"* "/opt/$programName/"
		#moves files to /opt/programDir/

		if [ "$programExe" != "null" ]; then	#as long as the program has an executable file, do
			echo "Removing old $programName symlink"
			sudo rm -f /usr/bin/$programName	#removes old symlink
			echo "Creating new $programName symlink"
			sudo ln -s /opt/$programName/$programExe /usr/bin/$programName	#custom for each program
			#creates symlink to bin
		fi
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
	programName=$(jq --argjson programIndex $programIndex -r '.[$programIndex].programName' 3rdPartyAutoUpdaterConf.json)	#gets the programName from .json and removes the "". The argjson parses the programIndex as an int insteaf of string
	programID=$(jq --argjson programIndex $programIndex -r '.[$programIndex].programID' 3rdPartyAutoUpdaterConf.json)	#gets the programID from .json and removes the "". The argjson parses the programIndex as an int insteaf of string
	url=$(jq --argjson programIndex $programIndex -r '.[$programIndex].url' 3rdPartyAutoUpdaterConf.json)	#gets the url from .json and removes the "". The argjson parses the programIndex as an int insteaf of string
	fetcherType=$(jq --argjson programIndex $programIndex -r '.[$programIndex].fetcherType' 3rdPartyAutoUpdaterConf.json)	#gets the fetcherType from .json and removes the "". The argjson parses the programIndex as an int insteaf of string
	binaryType=$(jq --argjson programIndex $programIndex -r '.[$programIndex].binaryType' 3rdPartyAutoUpdaterConf.json)	#gets the binaryType from .json and removes the "". The argjson parses the programIndex as an int insteaf of string
	programExe=$(jq --argjson programIndex $programIndex -r '.[$programIndex].programExe' 3rdPartyAutoUpdaterConf.json)	#gets the  (relative path to)  programExe from .json and removes the "". The argjson parses the programIndex as an int insteaf of string

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
