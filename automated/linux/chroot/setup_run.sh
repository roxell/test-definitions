#!/bin/bash

TEST_SUITE=${1}
TEST_PARAM_FILE=${2}

cd /
git clone https://github.com/Linaro/test-definitions new_root/testdef
echo "cat /etc/os-release" > new_root/run.sh
echo "cd /testdef/automated/linux/${TEST_SUITE}/" >> new_root/run.sh

awk "/params/{flag=1; next} /run/{flag=0} flag" new_root/testdef/automated/linux/${TEST_SUITE}/${TEST_SUITE}.yaml | sed 's/^ *//; s/: */=/' >> new_root/run.sh
cat new_root/testdef/automated/linux/chroot/${TEST_PARAM_FILE} >> new_root/run.sh
awk "/cd \.\/automated\/linux/{flag=1; next} /send-to-lava\.sh/{flag=0} flag" new_root/testdef/automated/linux/${TEST_SUITE}/${TEST_SUITE}.yaml | sed 's/^ *- *//' >> new_root/run.sh

cd -
