#!/bin/bash

collect_data () {
	source_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"	#Gets path of script
	if [[ "$1" != "SConstruct" && "$1" != "Makefile" ]];then
		echo "$1 is not a valid parameter. Please pass in either 'Makefile' or 'SConstruct'"
		return 1
	fi
	mkdir -p "$source_dir/results"

	#Make a new output file (If it already exists, it overrides it)
	output_filename="$source_dir/results/$1.csv"
	echo -e "\nRemoving previous $output_filename\n"
	echo "Repository name,File name,Lines added,Lines removed,Commits,File size (Bytes)" > $output_filename

	#For use in while loops getting data
	rm -f "$source_dir/mypipe"	#Delete the file if present
	mkfifo "$source_dir/mypipe"

	#Go into the repo with directories
	cd "repos/$1"
	current_dir=$(pwd)

	#Explore each project
	ls "$PWD" | while read x;do
		echo "Exploring project: $x"
		cd "$x"
		find . -name "$1" | while read y;do

			lines_added=0
			lines_removed=0
			count=0

			#Lines added
			git log --pretty=tformat: --numstat $y | cut -f 1 > "$source_dir/mypipe" &
			while IFS= read -r z
			do
				lines_added=$((lines_added + z))
				count=$((count + 1))
			done < "$source_dir/mypipe"
			
			#Lines removed
			git log --pretty=tformat: --numstat $y | cut -f 2 > "$source_dir/mypipe" &
			while IFS= read -r z
			do
				lines_removed=$((lines_removed + z))
			done < "$source_dir/mypipe"

			#Name of file
			name=$(echo "${y#*/}")

			#Get size of file (In bytes)
			file_size=$(stat --printf="%s" "$source_dir/repos/$1/$x/$name")

			#Output to csv
			echo "$x,$name,$lines_added,$lines_removed,$count,$file_size" >> $output_filename
			files_per_repo=$((files_per_repo + 1))
		done
		cd "$current_dir"
	done

	cd "$source_dir"

	echo -e "\n"

	#Now get the "files per repo" part, too hard to do it in above loop
	first=0
	count=0
	repo_name=''
	file_name=''
	sum_add=0
	sum_removed=0
	sum_commit=0
	file_size=0
	echo "" >> $output_filename
	echo "Repository,Files,Repository size (Bytes),Sum File size (Bytes),Repository age (EPOCH),Sum Lines added, Sum Lines removed, Sum No. Commits" >> $output_filename
	sum=-1
	while IFS= read -r line
	do
		if [ $first == 0 ];then	#Skip the header
			first=1
			continue
		fi

		#If either the file or repo name is different (On change)
		if [ "$repo_name" != "$(echo "$line" | cut -d',' -f 1)" ];then
			if [[ $file_name != '' || $repo_name != '' ]];then	#Ignores first call since its going from nothing to something
				repo_size=$(du -hcs -B1 "$source_dir/repos/$1/$repo_name" | head -n 1 | cut -f 1)	#Get size of repo in bytes
				cd "$source_dir/repos/$1/$repo_name"
				repo_age=$(date -d "$(git log --reverse --format="format:%ci" | sed -n 1p)" "+%s")	#You need to be in the repo for it to work.
																									#Also converts from GMT to EPOCH
				cd "$source_dir"
				
				echo "Creating new data for repository: $repo_name"
				echo "$repo_name,$count,$repo_size,$file_size,$repo_age,$sum_add,$sum_removed,$sum_commit" >> $output_filename
			fi
			count=0
			file_size=0
			sum_add=0
			sum_removed=0
			sum_commit=0
		fi
		repo_name=$(echo "$line" | cut -d',' -f 1)
		file_name=$(echo "$line" | cut -d',' -f 2)
		echo "Getting more info from: $repo_name"
		if [[ $file_name == '' || $repo_name == '' ]];then	#Detect the end of the previous data and stop
			break
		fi
		count=$((count + 1))
		sum=$((sum + 1))
		sum_add=$((sum_add + $(echo "$line" | cut -d',' -f 3)))
		sum_removed=$((sum_removed + $(echo "$line" | cut -d',' -f 4)))
		sum_commit=$((sum_commit + $(echo "$line" | cut -d',' -f 5)))
		file_size=$((file_size + $(echo "$line" | cut -d',' -f 6)))
	done < "$source_dir/results/$1.csv"
	echo "Total,$sum" >> $output_filename	#Adding a total to the bottom

	echo -e "\nFinished collecting data for $1\n"
}

collect_data "Makefile"
collect_data "SConstruct"
