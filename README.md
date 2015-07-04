# elasticsearch-s3-snapshot

This container can be used to easily manage Elasticsearch snapshots stored on an S3 repository.

This assumes you have installed and properly configured the Elasticsearch [cloud-aws](https://github.com/elastic/elasticsearch-cloud-aws) plugin.


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

```
