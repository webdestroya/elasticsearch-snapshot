#!/bin/bash

ELASTICSEARCH_URL=${ELASTICSEARCH_URL-"http://elasticsearch-9200.service.consul:9200"}
repo_name=${ESS_REPO_NAME?"You must include a repository name"}
create_if_missing=${ESS_CREATE_IF_MISSING-false}
max_snapshots=${ESS_MAX_SNAPSHOTS-0}
wait_for_completion=${ESS_WAIT_FOR_COMPLETION-true}
snapshot_prefix=${ESS_SNAPSHOT_PREFIX-"scheduled-"}
abort_if_empty=${ESS_ABORT_IF_EMPTY-true}

snapshot_timestamp=$(date -u +%s)
snapshot_name="${snapshot_prefix}${snapshot_timestamp}"

# Check to make sure elasticsearch is actually up and running
es_status=$(curl -s $ELASTICSEARCH_URL/ | jq --raw-output .status)
if [[ $es_status != "200" ]]; then
  echo "ERROR: Elasticsearch appears to be down?"
  exit 1;
fi

# Check to see if the repo exists and create if necessary
repository_exists=$(curl -s $ELASTICSEARCH_URL/_snapshot/ | jq --raw-output "has(\"$repo_name\")")
if [[ $repository_exists == "false" ]]; then
  if [[ $create_if_missing == "true" ]]; then

    repo_type=${ESS_REPO_TYPE?"You must provide the repository type"}
    #repo_settings=${ESS_REPO_SETTINGS?"You must provide the repository settings json"}

    echo "Repository '$repo_name' missing, creating"

    # Build up the JSON payload
    settings_list=()
    for VAR in `env`; do
      if [[ "$VAR" =~ ^ESS_REPO_SETTINGS_ ]]; then
        repo_setting_key=$(echo "$VAR" | gsed -r "s/ESS_REPO_SETTINGS_(.*)=.*/\1/g" | tr '[:upper:]' '[:lower:]')
        repo_setting_envvar=$(echo "$VAR" | gsed -r "s/(.*)=.*/\1/g")
        settings_list+=( $(printf '"%s":"%s"' $repo_setting_key ${!repo_setting_envvar}) )
      fi
    done
    settings_hash=$(printf ",%s" "${settings_list[@]}")
    settings_json=${settings_hash:1}
    json=$(printf '{"type":"%s","settings":{%s}}' $repo_type $settings_json)

    create_result=$(curl -s -XPUT $ELASTICSEARCH_URL/_snapshot/$repo_name -d $json)
    result=$(echo $create_result | jq --raw-output .acknowledged)
    if [[ $result == "true" ]]; then
      echo "Repository '$repo_name' created!"
    else
      echo "ERROR: Unable to create repository '$repo_name'"
      echo $create_result
      exit 3
    fi
  else
    echo "ERROR: Repository '$repo_name' does not exist!"
    exit 2
  fi
fi



if [[ $abort_if_empty == "true" ]]; then
  echo "Checking index count..."

  indices_count=$(curl -s $ELASTICSEARCH_URL/_stats/docs | jq --raw-output '.indices | length')
  if [[ $indices_count -eq 0 ]]; then
    echo "WARNING: This server has no indices and ESS_ABORT_IF_EMPTY was set to true"

    # exit with 0 because this is sort of a success
    exit 0
  fi
fi



# Check for existing number of snapshots
snapshot_list=$(curl -s $ELASTICSEARCH_URL/_snapshot/$repo_name/_all)

# Does this snapshot already exist??
already_exists_count=$(echo $snapshot_list | jq --raw-output ".snapshots[] | select(.state == \"SUCCESS\") | .snapshot" | grep -c $snapshot_name)
if [[ $already_exists_count -gt 0 ]]; then
  echo "ERROR: The snapshot '$snapshot_name' already exists in the repository '$repo_name'. Please wait 1 second."
  exit 4
fi

# We only bother with deletions if the max_snapshots is greater than 0
if [[ $max_snapshots -gt 0 ]]; then

  # How many of OUR snapshots already exist
  num_snapshots=$(echo $snapshot_list | jq "[.snapshots[] | select(.state == \"SUCCESS\") | select(.snapshot | startswith(\"$snapshot_prefix\")) | .snapshot] | length")

  # Check if we need to delete any
  if [[ $num_snapshots -ge $max_snapshots ]]; then
    num_snaps_to_remove=$(expr $num_snapshots - $max_snapshots)
    echo "Found $num_snapshots existing snapshots. Maximum is $max_snapshots. Deleting $num_snaps_to_remove older snapshots"

    for snapshot in $(echo $snapshot_list | jq --raw-output "[.snapshots[] | select(.state == \"SUCCESS\") | select(.snapshot | startswith(\"$snapshot_prefix\")) | .snapshot][0:$num_snaps_to_remove] | .[]"); do
      echo "Deleting snapshot $snapshot"

      del_result=$(curl -s -XDELETE $ELASTICSEARCH_URL/_snapshot/$repo_name/$snapshot)
      if [[ "$(echo $del_result | jq --raw-output .acknowledged)" == "true" ]]; then
        echo "Deleted snapshot $snapshot"
      else
        echo "WARNING: Unable to delete snapshot $snapshot"
        echo $(echo $del_result | jq --raw-output .error)
      fi
    done
  else
    echo "Found $num_snapshots existing snapshots. Maximum is $max_snapshots. No snapshots will be deleted."
  fi
else
  echo "Snapshot pruning has been disabled."
fi


# No deletions needed, so take a snapshot!
result=$(curl -s -XPUT "$ELASTICSEARCH_URL/_snapshot/$repo_name/scheduled-${snapshot_timestamp}?wait_for_completion=${wait_for_completion}")

if [[ $wait_for_completion == "true" ]]; then
  if [[ "$(echo $result | jq --raw-output .snapshot.state)" == "SUCCESS" ]]; then
    echo "Snapshot 'scheduled-$snapshot_timestamp' in '$repo_name' created"
    exit 0;
  fi
else
  if [[ "$(echo $result | jq --raw-output .accepted)" == "true" ]]; then
    echo "Snapshot 'scheduled-$snapshot_timestamp' in '$repo_name' created"
    exit 0;
  fi
fi

echo "ERROR: Failed to create snapshot 'scheduled-$snapshot_timestamp' in '$repo_name'"
echo $result
exit 5;
