# elasticsearch-s3-snapshot

This container can be used to easily manage Elasticsearch snapshots stored on an S3 repository.

This assumes you have installed and properly configured the Elasticsearch [cloud-aws](https://github.com/elastic/elasticsearch-cloud-aws) plugin.

## Environment Variables

* `ELASTICSEARCH_URL` *(default: `http://elasticsearch-9200.service.consul:9200`)*
  * The URL to reach your Elasticsearch server.
  * **NOTE**: This must be the **entire** hostname or IP. Hostnames that expect a search domain to be added will not work.
* `ESS_CREATE_IF_MISSING` *(defaut: false)*
  * If this is `true` and the snapshot repository does not exist, then attempt to create it.
* `ESS_MAX_SNAPSHOTS` *(defaut: 100)*
  * The maximum number of snapshots to allow. Set to `0` to disable entirely.
  * Note: Only snapshots with a `scheduled-` prefix will be counted and deleted. All other snapshots will not count against this limit.
* `ESS_REPO_NAME` **required**
  * The name of the repository to create snapshots under.
* `ESS_WAIT_FOR_COMPLETION` *(default: true)*
  * Whether the execution should wait until the snapshot has been created before exiting.

If `ESS_CREATE_IF_MISSING` is set to `true` then the following are **required**:
* `ESS_REPO_SETTINGS`
  * A json payload that represents the `settings` part of a repository creation.
* `ESS_REPO_TYPE`
  * The repository type field. Common ones include `fs` and `s3`.

For more details about repository creation, see the [Elasticsearch documentation](https://www.elastic.co/guide/en/elasticsearch/reference/1.6/modules-snapshots.html#_repositories)

## Usage
This is best used with a timer and service combination in your cluster.

```
# elasticsearch-snapshot.timer
[Unit]
Description=Elasticsearch Scheduled Snapshot Timer

[Timer]
OnCalendar=hourly
Persistent=false

[Install]
WantedBy=multi-user.target

[X-Fleet]
Conflicts=%p.timer
MachineOf=%p.service
```

```
# elasticsearch-snapshot.service
[Unit]
Description=Elasticsearch Scheduled Snapshot
Requires=docker.service
After=docker.service

[Service]
TimeoutStartSec=0
Type=simple

ExecStartPre=-/usr/bin/docker pull webdestroya/elasticsearch-snapshot

ExecStart=/usr/bin/docker run --rm=true \
  -e ELASTICSEARCH_URL=http://elasticsearch-9200.service.consul:9200 \
  -e ESS_REPO_NAME=s3_repository \
  -e ESS_MAX_SNAPSHOTS=100 \
  -e ESS_WAIT_FOR_COMPLETION=true \
  webdestroya/elasticsearch-snapshot

[Install]
WantedBy=multi-user.target

[X-Fleet]
Conflicts=%p.service
```
