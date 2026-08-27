# Architecture

```text
Docker/Coolify container (immutable launcher)
  ├── ttyd :7681
  │    └── PRoot -> /state/rootfs -> zsh
  └── OpenCode Web :4096
       └── PRoot -> /state/rootfs -> opencode

/state/rootfs    = persistent machine userspace
/mnt/workspace   = selected storage in the outer container
/home/workspace  = workspace-backed home inside PRoot
```

PRoot provides a chroot-like userspace and fake root identity; it does not provide a guest kernel, systemd VM semantics, cgroups, kernel modules, or Docker-in-Docker. The outer Docker container remains the security boundary.

Each web-shell browser tab gets a fresh ttyd PTY and a fresh zsh login. Closing the tab closes that shell; there is no tmux.

The workspace volume is the complete home: projects and optional directories such as `vaults/` sit directly below `/home/workspace`. System packages live in `/state/rootfs`, while home-scoped tools and dotfiles live in the workspace volume.

OpenCode supports directory-scoped web routes internally. Use `workspace-url <path>` inside the shell to print a direct URL for a directory under the home.
