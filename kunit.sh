#!/bin/bash

#echo "TAP version 14" >> tap_14_results.txt
#dmesg| sed '1,/TAP version 14/d'|tee tap_14_results.txt
#cat job_1801301.log| sed '1,/TAP version 14/d'|tee tap_14_results.txt
cp tap_14_results.txt tap_14_results2.txt
LAST_LINE=$(cat tap_14_results2.txt| grep '# Subtest: '| awk -F '# Subtest:' '{print $2}'|tail -1)
echo apa $LAST_LINE apa
sed -i "/- $LAST_LINE/q" tap_14_results2.txt
cat tap_14_results2.txt
