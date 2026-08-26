# Storage contract

The runtime has exactly two storage contracts:

- `/state`: persistent Linux userspace. Must provide POSIX filesystem semantics. Use a Docker volume, local/block storage, or a suitable NFS filesystem. Do not put this on S3/object storage.
- `/workspace`: user data. It can be a Docker volume, bind mount, NFS, distributed filesystem, or a separately mounted object-storage adapter.

The runtime never derives `/workspace` from `WORKSPACE_NAME`. `WORKSPACE_NAME` is metadata only.

## S3

S3 is not a POSIX filesystem. Mount it outside the core runtime with rclone/s3fs/another adapter and provide the resulting mount as `/workspace`. This is appropriate for Markdown/media/document repositories; it is not recommended for active `.git`, `node_modules`, build trees, file locks, or watcher-heavy workloads.
