#!/usr/bin/env bash

# Enable strict error checking
set -e

# Function to display messages to the user
show_message() {
	echo "$1"
}

# Function to enable debug mode
enable_debug() {
	set -x
}

# Function to show the FZF menu and get the selected package name
get_selected_package() {
	local selected_pkg
	selected_pkg=$(adb shell pm list packages --user 0 | cut -d ":" -f2 | fzf)
	echo "$selected_pkg"
}

# Function to perform the installation
install_package() {
	local pkg="$1"

	pkg_name=$(adb shell pm list packages --user 0 | grep "$pkg" | cut -d ":" -f2 | tr -d '[:space:]')
	if [[ -z "$pkg_name" ]]; then
		show_message "Invalid package selected. Please select a valid package."
		get_selected_package
		return
	fi

	show_message "Package name: $pkg_name"

	pkg_path=$(adb shell pm path "$pkg_name" | cut -d ":" -f2 | head -n 1 | rev | cut -d "/" -f 2- | rev)
	show_message "Package path: $pkg_path"

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
	show_message "Total APKs size: $TOTAL_APKS_SIZE"

	SESSION_ID=$(adb shell pm install-create -S $TOTAL_APKS_SIZE | cut -d "[" -f2 | cut -d "]" -f1)
	show_message "Session ID: $SESSION_ID"

	## Get a list of all the APKs in the package directory
	apk_list=$(adb shell "cd $pkg_path; ls")

	## Loop through each APK and stage it for installation
	index=1
	for apk in $apk_list; do
		apk_size=$(adb shell stat -c %s "$pkg_path/$apk")
		show_message "Staging APK: $apk (size: $apk_size)"
		adb shell pm install-write -S "$apk_size" "$SESSION_ID" "${index}_$apk" "$pkg_path/$apk"
		index=$((index + 1))
	done

	echo "Please be patient committing package install!"
	## Check if all APKs have been staged successfully
	if [[ $((index - 1)) -eq $(echo "$apk_list" | wc -w) ]]; then
		## Commit the installation
		adb shell pm install-commit "$SESSION_ID"
		show_message "Installation committed successfully"

		## Remove the APKs from the temporary directory on the device
		adb shell rm -rf "$pkg_path"
	else
		show_message "Failed to stage all APKs. Aborting installation."
	fi
}

# Function to check if any ADB device is available
check_adb_devices() {
	if ! adb devices | grep -q 'device$'; then
		show_message "No ADB devices connected. Please connect a device and try again."
		exit 1
	fi
}

# Function to display the usage menu
show_usage() {
	show_message "Usage: $0 [-d|--debug] [-h|--help] [package_name]"
	show_message "Options:"
	show_message "  -d, --debug   Enable debug mode"
	show_message "  -h, --help    Show usage menu"
}

# Main script
main() {
	# Check for flags
	if [[ "$1" == "-d" || "$1" == "--debug" ]]; then
		enable_debug
		shift
	elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
		show_usage
		exit 0
	elif [[ -n "$1" ]]; then
		if [[ "${1:0:1}" == "-" ]]; then
			show_message "Invalid flag: $1"
			show_usage
			exit 1
		fi
	fi

	check_adb_devices

	# Check if package name is passed or show FZF menu
	if [[ -z "$1" ]]; then
		package_name=$(get_selected_package)
		if [[ -z "$package_name" ]]; then
			show_message "No package selected. Exiting."
			exit 1
		fi
		install_package "$package_name"
	else
		install_package "$1"
	fi
}

main "$@"
