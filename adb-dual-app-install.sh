#!/usr/bin/env bash
set -x # Enable debugging
#pm is just a wrapper for
#cmd package "@"

if [[ -z $1 ]]; then
	$0 $(adb shell pm list packages --user 0 | cut -d ":" -f 2 | fzf)
else
	pkg="$1"
	if [[ $(adb devices | wc -l) -gt 2 ]]; then
		pkg_name=$(adb shell pm list packages --user 0 | grep "$pkg" | cut -d ":" -f2 | tr -d '[:space:]')
		echo "Package name: $pkg_name"

		pkg_path=$(adb shell pm path "$pkg_name" | cut -d ":" -f2 | head -n 1 | rev | cut -d "/" -f 2- | rev)
		echo "Package path: $pkg_path"

		# Create the directory on the device to store the split APKs
		adb shell mkdir -p "/data/local/tmp/$pkg_name"

		## Copy the split APKs from user 0 to the device
		adb shell cp -r "$pkg_path/*.apk" "/data/local/tmp/$pkg_name/"

		pkg_path="/data/local/tmp/$pkg_name"

		## Perform the installation for user 95
		TOTAL_APKS_SIZE=0
		for apk in $(adb shell find "$pkg_path" -type f); do
			apk_size=$(adb shell stat -c %s "$apk")
			TOTAL_APKS_SIZE=$((TOTAL_APKS_SIZE + apk_size))
		done
		echo $TOTAL_APKS_SIZE

		SESSION_ID=$(adb shell pm install-create -S $TOTAL_APKS_SIZE | cut -d "[" -f2 | cut -d "]" -f1)
		echo "Session ID: $SESSION_ID"

		## Get a list of all the APKs in the package directory
		apk_list=$(adb shell "cd $pkg_path; ls")

		## Loop through each APK and stage it for installation
		index=1
		for apk in $apk_list; do
			apk_size=$(adb shell stat -c %s "$pkg_path/$apk")
			echo "Staging APK: $apk (size: $apk_size)"
			adb shell pm install-write -S "$apk_size" "$SESSION_ID" "${index}_$apk" $pkg_path/$apk
			index=$((index + 1))
		done

		## Check if all APKs have been staged successfully
		if [[ $((index - 1)) -eq $(echo "$apk_list" | wc -w) ]]; then
			## Commit the installation
			adb shell pm install-commit "$SESSION_ID"
			echo "Installation committed successfully"

			## Remove the APKs from the temporary directory on the device
			adb shell rm -rf "$pkg_path"
		else
			echo "Failed to stage all APKs. Aborting installation."
		fi
	else
		echo "No devices connected via ADB!"
	fi
fi
