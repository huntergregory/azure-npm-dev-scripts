#!/bin/bash
if [[ -z $1 ]]; then
	echo "pass a filename as an argument"
	exit 1
fi
file=$1
tmpFile=$1.tmp
sed -r 's/.{29}//' $file > $tmpFile && mv $tmpFile $file
