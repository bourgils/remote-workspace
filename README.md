# Remote Workspace

Use any volume, bind mount, or remote filesystem as a persistent Linux home and get two browser interfaces:

- **Web shell** on port `7681`: each browser tab is a fresh SSH-like zsh session; closing the tab ends that shell.
- **OpenCode Web** on port `4096`: OpenCode runs inside the same persistent userspace and opens on the same home.

The design has two independent storage layers:

```text
/state/rootfs    -> persistent machine (apt packages, /etc, /usr, /opt)
/home/workspace  -> workspace-backed home (projects, vaults, dotfiles, OpenCode state)
```

The selected storage is mounted at `/mnt/workspace` by the outer container and injected as `/home/workspace` inside the persistent userspace. `WORKSPACE_NAME` is metadata only.

## Default machine

The persistent Debian userspace includes:

- OpenCode
- git
- qmd (`@tobilu/qmd`)
- zsh + Oh My Zsh with command completion, autosuggestions, syntax highlighting, Git prompt and shared history
- Oh My Zsh `git` and `sudo` plugins
- curl, wget, jq, ripgrep, fzf, vim/nano, SSH client
- Bun

Because `/state/rootfs` persists, normal machine mutations persist too:

```bash
apt update
apt install -y apache2
bun add -g <package>
npm install -g <package>
```

System changes remain in `machine-state`. Projects, dotfiles, NVM installations, and OpenCode user state remain in `workspace-data`.

## Local deployment

```bash
cp .env.example .env
# Set OPENCODE_SERVER_PASSWORD in .env
docker compose up -d --build
```

Then open:

- `http://localhost:4096` — OpenCode Web
- `http://localhost:7681` — Web shell

The default Compose publishes both ports for local development.

## OpenCode directory URLs

OpenCode's current web UI uses a base64-encoded absolute directory in its route. Inside the web shell:

```bash
workspace-url ~
workspace-url ~/vaults/Personal
```

Set `OPENCODE_PUBLIC_URL=https://oc.example.com` if you want generated links to use your public domain. The helper refuses paths that resolve outside the home.

## Coolify

Build/publish the image to GHCR, then create a Docker Compose resource from this repository.

To build directly from the repository, use:

```text
dist/coolify-build.yaml
```

If you publish the OCI image to GHCR first, use `dist/coolify-volume.yaml`.

For the workspace and Ignis sharing the same on-demand volume through Wakewrap, use `dist/coolify-obsidian.yaml`.

Required variables:

```env
WORKSPACE_NAME=personal
WORKSPACE_RUNTIME_IMAGE=ghcr.io/YOUR_ORG/remote-workspace:latest
OPENCODE_SERVER_PASSWORD=...
SHELL_USERNAME=workspace
SHELL_PASSWORD=...
```

Additional variables for the Obsidian preset:

```env
OBSIDIAN_USERNAME=obsidian
OBSIDIAN_PASSWORD_HASH=<bcrypt hash generated with htpasswd -nbB>
```

For the Obsidian preset, assign three domains in Coolify:

```text
oc.example.com    -> workspace:4096
shell.example.com -> workspace:7681
notes.example.com -> obsidian:8080
```

The Coolify presets use only `expose`, not host `ports`.
The Obsidian preset protects Ignis with a Traefik Basic Auth middleware. Use HTTPS.

For a host/NAS mount use `dist/coolify-bind.yaml` and set:

```env
WORKSPACE_HOST_PATH=/mnt/vaults/personal
```

## Other storage

The core runtime only requires that the selected storage appears at `/mnt/workspace` in the outer container. It becomes `/home/workspace` inside the persistent userspace.

- Docker volume: default `compose.yaml`
- Existing Docker volume: overlay `storage/external-volume.compose.yaml`
- NFS: overlay `storage/nfs.compose.yaml`
- Bind mount: `dist/coolify-bind.yaml` or edit the local Compose
- S3/object storage: mount through a dedicated external adapter, then bind the resulting mount to `/mnt/workspace`

Example NFS:

```bash
NFS_SERVER=10.0.0.5 NFS_PATH=/exports/vaults \
  docker compose -f compose.yaml -f storage/nfs.compose.yaml up -d
```

See `docs/STORAGE.md`.

## Obsidian

Obsidian is intentionally not part of the core. `examples/obsidian/compose.yaml` demonstrates the contract: mount the entire home volume in Ignis and set `VAULT_ROOT` to its `vaults` subdirectory.

In the Coolify Obsidian preset, the shell and OpenCode start in `/home/workspace`; only `vaults/` is created automatically. Ignis mounts the same volume at `/workspace` and uses `/workspace/vaults` as its vault root.

## Security and VM semantics

This is a persistent **Linux userspace**, not a full VM. PRoot uses the host kernel. Do not expect systemd, kernel modules, privileged mounts, cgroups management, or Docker-in-Docker inside the guest.

The outer Docker container remains the isolation boundary. Do not mount the Docker socket and do not run the container privileged.

## Image updates vs machine updates

The initial guest filesystem is copied into `/state/rootfs` once. Rebuilding/updating the OCI image does not overwrite an existing machine. This is intentional: the persistent machine belongs to the user.

To get a fresh machine while retaining the home, remove only the `machine-state` volume. To reset projects, dotfiles, and OpenCode user state, remove `workspace-data` as well.
