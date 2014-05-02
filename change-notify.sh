#!/bin/bash

set -ex

EXPECTED_ARGS=4
E_BADARGS=65

if [ $# -ne ${EXPECTED_ARGS} ]
then
    echo "Usage: `basename $0` {repo} {before commit ID} {after commit ID} {ref}"
    exit ${E_BADARGS}
fi

#export PATH="$HOME/.rbenv/bin:/usr/local/bin:$PATH"
#eval "$(rbenv init - bash)"
#rbenv rehash
#echo $PATH

REPO=$1
BEFORE=$2
AFTER=$3
REF=$4
CONFIG=/etc/git-commit-notifier-config.yml
echo "PWD=$(pwd)"

# Assume repository exists in directory and user has already pulled
cd ${GITDUB_HOME}/${REPO}-nobare
git pull --rebase
echo "PWD=$(pwd)"
echo ${BEFORE} ${AFTER} ${REF} | git-commit-notifier ${CONFIG} 2>&1 >>/var/log/git-commit-notifier.log

# this is a comment
