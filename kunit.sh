#!/bin/bash

#echo "TAP version 14" >> tap_14_results.txt
#dmesg| sed '1,/TAP version 14/d'|tee tap_14_results.txt
#cat job_1801301.log| sed '1,/TAP version 14/d'|tee tap_14_results.txt
cp tap_14_results.txt tap_14_results2.txt
#LAST_LINE=$(cat tap_14_results2.txt| grep '# Subtest: '| awk -F '# Subtest:' '{print $2}'|tail -1)
#sed -i "/- $(echo $LAST_LINE)/q" tap_14_results2.txt
for tests in $(cat tap_14_results2.txt| grep '# Subtest: '| awk -F '# Subtest:' '{print $2}'); do
	my_start=$(grep -n $tests tap_14_results2.txt|head -1|awk -F ':' '{print $1}')
	my_end=$(grep -n $tests tap_14_results2.txt|tail -1|awk -F ':' '{print $1}')
	#sed -n ${my_start},${my_end}p tap_14_results2.txt|grep -Eo "(not )?ok [0-9]{1,4} - .*"|awk -F' ' '{print "."$4": "$1}'|sed "s/^/$tests/g"
	sed -n ${my_start},${my_end}p tap_14_results2.txt|grep -Eo "(not )?ok [0-9]{1,4} - .*"\
		|awk -F' ' '{print ($NF ~ /SKIP/)?"."$4": SKIP":"."$4": "$1}'|sed "s/^/$tests/g"
done
