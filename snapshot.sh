#!/bin/bash

ELASTICSEARCH_URL=${ELASTICSEARCH_URL-"http://elasticsearch-9200:9200"}
repo_name=${ESS_REPO_NAME?"You must include a repository name"}
create_if_missing=${ESS_CREATE_IF_MISSING-false}
max_snapshots=${ESS_MAX_SNAPSHOTS-100}
wait_for_completion=${ESS_WAIT_FOR_COMPLETION-true}

snapshot_timestamp=$(date -u +%s)

# Check to see if the repo exists and create if necessary
repository_exists=$(curl -s $ELASTICSEARCH_URL/_snapshot/ | jq --raw-output "has(\"$repo_name\")")
if [[ $repository_exists == "false" ]]; then
  if [[ $create_if_missing == "true" ]]; then

    repo_type=${ESS_REPO_TYPE?"You must provide the repository type"}
    repo_settings=${ESS_REPO_SETTINGS?"You must provide the repository settings json"}

    echo "Repository '$repo_name' missing, creating"

    create_result=$(curl -s -XPUT $ELASTICSEARCH_URL/_snapshot/$repo_name -d "{\"type\":\"$repo_type\",\"settings\":$repo_settings}")

    result=$(echo $create_result | jq --raw-output .acknowledged)
    if [[ $result == "true" ]]; then
      echo "Repository '$repo_name' created!"
    else
      echo "ERROR: Unable to create repository '$repo_name'"
      echo $create_result
      exit 1
    fi
  else
    echo "ERROR: Repository '$repo_name' does not exist!"
    exit 1;
  fi
fi

# Check for existing number of snapshots
snapshot_list=$(curl -s $ELASTICSEARCH_URL/_snapshot/$repo_name/_all)

# Does this snapshot already exist??
already_exists_count=$(echo $snapshot_list | jq --raw-output ".snapshots[].snapshot | contains(\"scheduled-$snapshot_timestamp\")" | grep -c true)
if [[ $already_exists_count -gt 0 ]]; then
  echo "ERROR: The snapshot 'scheduled-$snapshot_timestamp' already exists in the repository '$repo_name'. Please wait 1 second."
  exit 1
fi

# We only bother with deletions if the max_snapshots is greater than 0
if [[ $max_snapshots -gt 0 ]]; then

  # How many of OUR snapshots already exist
  num_snapshots=$(echo $snapshot_list | jq --raw-output ".snapshots[].snapshot" | grep -E ^scheduled- | wc -l)

  # Check if we need to delete any
  if [[ $num_snapshots -ge $max_snapshots ]]; then
    num_snaps_to_remove=$(expr $num_snapshots - $max_snapshots)
    echo "Found $num_snapshots existing snapshots. Maximum is $max_snapshots. Deleting $num_snaps_to_remove older snapshots"

    for snapshot in $(echo $snapshot_list | jq --raw-output ".snapshots[].snapshot" | grep -E ^scheduled- | head -n $num_snaps_to_remove ); do
      echo "Deleting snapshot $snapshot"

      curl -s -XDELETE $ELASTICSEARCH_URL/_snapshot/$repo_name/$snapshot
    done
  fi

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
exit 1;
