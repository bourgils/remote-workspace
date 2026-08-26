# Architecture

```text
Docker/Coolify container (immutable launcher)
  ├── ttyd :7681
  │    └── PRoot -> /state/rootfs -> zsh
  └── OpenCode Web :4096
       └── PRoot -> /state/rootfs -> opencode

/state/rootfs  = persistent machine userspace
/workspace     = injected user workspace
```

PRoot provides a chroot-like userspace and fake root identity; it does not provide a guest kernel, systemd VM semantics, cgroups, kernel modules, or Docker-in-Docker. The outer Docker container remains the security boundary.

Each web-shell browser tab gets a fresh ttyd PTY and a fresh zsh login. Closing the tab closes that shell; there is no tmux.

OpenCode supports directory-scoped web routes internally. Use `workspace-url <path>` inside the shell to print a direct URL for a directory under `/workspace`.
