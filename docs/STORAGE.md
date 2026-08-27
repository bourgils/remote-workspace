# Storage contract

The runtime has exactly two storage contracts:

- `/state`: persistent Linux system. Must provide POSIX filesystem semantics. Use a Docker volume, local/block storage, or a suitable NFS filesystem. Do not put this on S3/object storage.
- `/mnt/workspace`: complete user home source. It can be a Docker volume, bind mount, NFS, distributed filesystem, or a separately mounted object-storage adapter. PRoot exposes it as `/home/workspace`.

The runtime never derives the home path from `WORKSPACE_NAME`. `WORKSPACE_NAME` is metadata only.

## S3

S3 is not a POSIX filesystem. Mount it outside the core runtime with rclone/s3fs/another adapter and provide the resulting mount as `/mnt/workspace`. This is appropriate for Markdown/media/document repositories; it is not recommended for active `.git`, `node_modules`, build trees, file locks, or watcher-heavy workloads.
