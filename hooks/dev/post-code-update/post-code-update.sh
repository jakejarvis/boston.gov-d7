#!/bin/bash
#
# Cloud Hook: post-code-update
#
# The post-code-update hook runs in response to code commits.
# When you push commits to a Git branch, the post-code-update hooks runs for
# each environment that is currently running that branch.. See
# ../README.md for details.
#
# Usage: post-code-update site target-env source-branch deployed-tag repo-url
#                         repo-type
#
# @see readme.md for City of Boston specific notes.
#

site="$1"
target_env="$2"
source_branch="$3"
deployed_tag="$4"
repo_url="$5"
repo_type="$6"

# Add utility functions
. "/var/www/html/${site}.${target_env}/hooks/common/cob_utilities.sh"

echo -e "\n$site.$target_env: A successful commit to $source_branch branch has caused a code update on $target_env environment of $site environment."

echo "This hook will now synchronise the $target_env database with updated code."

# Use acapi command (rather than drush db-dump) because this will cause the backup
# to be shown the the acquia UI.
echo "- Backing up the current $site database on ${target_env}."
TASK=$(drush @${site}.${target_env} ac-database-instance-backup ${site} --email=${ac_api_email} --key=${ac_api_key} --endpoint=https://cloudapi.acquia.com/v1 --format=json)
RES=$(monitor_task "${TASK}" "@${site}.${target_env}" 500)
echo "Result: ${RES}"
if [ "${RES}" != "done" ]; then
    echo -e "\nERROR BACKING UP DATABASE IN DEV ENVIRONMENT.\n"
fi

# Use acapi command (rather than sql-sync) because this will cause the Acquia DB copy hooks to run.
# The acapi command runs an async task, so we have to wait for the copy to complete
# before performing any DB sync activity
echo "- Copy database from stage (aka test) to $target_env."
TASK=$(drush @${site}.test ac-database-copy ${site} ${target_env} --email=${ac_api_email} --key=${ac_api_key} --endpoint=https://cloudapi.acquia.com/v1 --format=json)
RES=$(monitor_task "${TASK}" "@${site}.test" 1200)
echo "Result: ${RES}"
if [ "${RES}" != "done" ]; then
    echo -e "\nERROR COPYING DATABASE FROM STAGE ENVIRONMENT."
    exit 1
fi

# Sync the copied database with the recently updated/deployed code.
echo "- Update database ($site) on $target_env with configuration from updated code in $source_branch."
sync_db @${site}.${target_env}

drush @${site}.${target_env} en stage_file_proxy -y
drush @${site}.${target_env} vset "stage_file_proxy_origin" "https://www.boston.gov"
drush @${site}.${target_env} vset "asset_url" "https://cob-patterns-staging.herokuapp.com"
