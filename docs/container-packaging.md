# Container packaging

The image packages official AMP 3 binaries without modifying them. AMP owns its supervisor, message bus, system agent, shard accounts, server permissions, updates, and game lifecycle.

## Container initialization

- The build uses APT to authenticate and download the official amp3 and amp3-sysagent packages, then extracts their payloads. It does not execute AMP maintainer scripts or register these packages as installed in dpkg. System packages and Java use their normal package installers.
- main.sh validates container settings, prepares data, and starts systemd as PID 1.
- prepare-data.py changes directory ownership through no-follow descriptors and maintains a private persistent machine ID. It does not recursively chown regular data files or change host sysctls. Existing machine IDs retain their value and have group/other permissions removed.
- amp3-bootstrap.service directly runs seed-data.py as amp. Seed files and initial settings are created by their intended owner. Existing usable versions are retained; incomplete or blacklisted seeds stop initialization for manual review.
- The vendor services retain their supplied units, with a small drop-in for bootstrap ordering and console logging. Login prompts and automatic APT timers are disabled; package maintenance is through image rebuilds or explicit operations.

This replaces only the installer responsibilities needed for a container. The official post-install scripts require fs.protected_hardlinks=1 before handing regular files to amp as root. This image avoids that ownership handover rather than changing or falsifying the host setting.

## Native servers need systemd

The official amp3 package's per-shard-identity.md describes Linux native shards launched as transient systemd services. Without systemd-run, native launching is refused with native.noSystemd. Cgroups are the process boundary for these services. The host cgroup namespace and writable cgroup mount resolved the observed Unraid /init.scope mismatch; the current capability settings remain until narrower settings are verified.

## Filesystem permissions

The image omits ACL utilities. AMP's documented fallback for missing setfacl grants traversal on selected ancestor directories and read/execute access to the shared agent binaries, after checking the privacy of neighboring entries. Secret files and individual shard directories retain their restricted permissions. This is less restrictive than group-only ACL traversal, and is used on all hosts to keep the integration small.

On the tested Unraid FUSE user share, ACL entries were visible but did not allow an isolated shard account to traverse the data root. Selecting AMP's fallback allowed SteamCMD installation and Valheim startup while retaining the user-share path. No custom permissions manager, tool wrapper, binary rename, or runtime storage detector is included. A final build check rejects setfacl if another dependency unexpectedly introduces it. The vendor safety checks remain unchanged.

## Validation

The earlier extracted-package staging image built successfully. On Unraid, the machine-ID permissions were tightened and setfacl was temporarily removed for diagnosis; Valheim subsequently installed and reached Running, Opened Steam server, and Loading: Done. These observations validate the approach, not the newly edited image.

The integrated changes still need an image build, a client connection, stop/start checks, and container restart/recreation against retained data. New images must preserve machine identity, private data, and usable versions without manual permissions changes. Test isolation between two shards before declaring full lifecycle support. Do not publish or merge without the owner's approval.
