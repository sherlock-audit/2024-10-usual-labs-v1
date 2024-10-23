#!/usr/bin/env bash

cd `dirname "$0"`/..

errors=`grep -RhE '^error \w+\([^)]*\)\;$' .`

IFS=$'\n'
for error in $errors
do
    signature="${error:6:-1}"
    hash=`cast sig "$signature"`
    echo "${hash:2}: $signature"
done
