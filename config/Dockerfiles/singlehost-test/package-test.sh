#!/bin/bash
set -e

CURRENTDIR=$(pwd)
if [ ${CURRENTDIR} == "/" ] ; then
    cd /home
    CURRENTDIR=/home
fi
export TEST_ARTIFACTS=${CURRENTDIR}/logs
if [ -z "${TEST_SUBJECTS:-}" ]; then
    export TEST_SUBJECTS=${CURRENTDIR}/untested-atomic.qcow2
fi
if [ -z "${TEST_LOCATION:-}" ]; then
    export TEST_LOCATION=https://src.fedoraproject.org/rpms/${package}
fi
if [ -z "${TAG:-}" ]; then
    export TAG=atomic
fi
# The test artifacts must be an empty directory
rm -rf ${TEST_ARTIFACTS}
mkdir -p ${TEST_ARTIFACTS}

# It was requested that these tests be run with latest rpm of standard-test-roles
# Try to update for few times, if for some reason could not update,
# continue test with installed STR version
str_attempts=1
while [ $str_attempts -le 5 ]; do
    if yum update -y standard-test-roles; then
        break
    fi
  ((str_attempts++))
done
rpm -q standard-test-roles

# Invoke tests according to section 1.7.2 here:
# https://fedoraproject.org/wiki/Changes/InvokingTests

if [ -z "${package:-}" ]; then
	if [ $# -lt 1 ]; then
		echo "No package defined"
		exit 2
	else
		package="$1"
	fi
fi

namespace=${namespace:-"rpms"}

tests_path="tests"
if [ "${namespace}" == "tests" ]; then
    tests_path="."
fi

# Make sure we have or have downloaded the test subject
if [ -z "${TEST_SUBJECTS:-}" ]; then
	echo "No subject defined"
	exit 2
elif ! file ${TEST_SUBJECTS:-}; then
	wget -q -O testimage.qcow2 ${TEST_SUBJECTS}
	export TEST_SUBJECTS=${PWD}/testimage.qcow2
fi

# Check out the dist-git repository for this package
rm -rf ${package}
if ! git clone ${TEST_LOCATION}; then
	echo "No dist-git repo for this package! Exiting..."
	exit 0
fi

# The specification requires us to invoke the tests in the checkout directory
pushd ${package}

# Check out the appropriate branch and rev
if [ -z ${build_pr_id} ]; then
    git checkout ${branch}
    git checkout ${rev}
else
    git checkout ${branch}
    git fetch -fu origin refs/pull/${build_pr_id}/head:pr
    # Setting git config and merge message in case we try to merge a closed PR, like it is done on stage instance
    git -c "user.name=Fedora CI" -c "user.email=ci@lists.fedoraproject.org"  merge pr -m "Fedora CI pipeline"
fi

# Check if there is a tests dir from dist-git, if not, exit
if [ -d ${tests_path} ]; then
     pushd ${tests_path}
else
     echo "No tests for this package! Exiting..."
     exit 0
fi

# This will introduce a problem with concurrency as it has no locks
function clean_up {
    rm -rf tests/package
    mkdir -p tests/package
    cp -rp ${TEST_ARTIFACTS}/* tests/package/
    cat ${TEST_ARTIFACTS}/test.log
    set +u
    if [[ ! -z "${RSYNC_USER}" && ! -z "${RSYNC_SERVER}" && ! -z "${RSYNC_DIR}" && ! -z "${RSYNC_PASSWORD}"  && ! -z "${RSYNC_BRANCH}" ]]; then
        RSYNC_LOCATION="${RSYNC_USER}@${RSYNC_SERVER}::${RSYNC_DIR}/${RSYNC_BRANCH}"
        rsync --stats -arv tests ${RSYNC_LOCATION}/repo/${package}_repo/logs
    fi
}
trap clean_up EXIT SIGHUP SIGINT SIGTERM

# The inventory must be from the test if present (file or directory) or defaults
if [ -e inventory ] ; then
    if [ ! -x inventory ] ; then
        echo "FAIL: tests/inventory file must be executable"
        exit 1
    fi
    ANSIBLE_INVENTORY=$(pwd)/inventory
    export ANSIBLE_INVENTORY
fi

set +u
PYTHON_INTERPRETER=""

if [[ ! -z "${python3}" && "${python3}" == "yes" ]] ; then
    PYTHON_INTERPRETER='--extra-vars ansible_python_interpreter=/usr/bin/python3'
fi
set -u

# Invoke each playbook according to the specification
set -xo pipefail
for playbook in tests*.yml; do
	if [ -f ${playbook} ]; then
		ANSIBLE_STDOUT_CALLBACK=yaml timeout 4h ansible-playbook -v --inventory=$ANSIBLE_INVENTORY $PYTHON_INTERPRETER \
			--tags ${TAG} ${playbook} $@ | tee ${TEST_ARTIFACTS}/${playbook}-run.txt
	fi
done
popd
popd
