# Picotool wrapper contract 1

The root and `zigmkay` package build APIs expose
`flash_wrapper_contract_version = 1`. Preparation with Zig 0.17.0 is explicit:

```sh
~/.zvm/0.17.0/zig build -Dflash-tools=true
```

This installs `picotool_flash` and the pinned `picotool` in `zig-out/bin`.
Downstream consumers can use `artifact("picotool_flash")` and
`namedLazyPath("picotool")`. Preparation builds executables; it does not discover
or flash a device. Normal builds/tests leave the optional picotool dependency
unresolved. `zig build test-picotool` runs only Zig fixtures without USB access.

The existing two positional arguments remain supported. Additional flags:

| Flag | Contract |
| --- | --- |
| `--sha256 HEX` | Expected 64-character SHA-256; mismatch stops before picotool execution |
| `--discovery-ms N` | BOOTSEL discovery budget, default 30000 milliseconds |
| `--command-ms N` | Per-command budget, default 60000 milliseconds, including child wait |
| `--bus N --address N` | Complete USB target filter; bus 0–255 and address 1–127 |
| `--serial S` | Alternative target filter, forwarded as picotool `--ser` |
| `--cancel-stdin` | Any byte or EOF requests cancellation; owner must keep stdin open until then |

Budgets must be 1–3600000 milliseconds. Duplicate/unknown flags, incomplete
bus/address pairs and combining serial with bus/address are rejected.
All arguments are passed literally, without a shell. Filter semantics and
exit status 249 for absence are tied to pinned picotool 2.3.1 sources.

UF2 validation requires complete ordered 512-byte blocks with magic words,
256-byte payloads, RP2040 family flags/ID and a matching block count. The file is
hashed before discovery and re-read before load to reject replacement while
waiting. Managed callers must additionally supply a frozen job artifact,
expected hash and explicit BOOTSEL selection. A HID identity does not establish
that selection. The mutable standalone path cannot prevent a concurrent write
between the final check and picotool opening it.

Discovery rejects picotool's literal multiple-device diagnostic, retries only
its no-device exit status, and bounds both polling and stalled children.
Standalone unselected operation also rechecks ambiguity before reboot because
picotool reboot supports multiple devices. This is not continuous device
identity tracking; managed callers must select a target and native acceptance
must cover disconnect/replacement between commands.

Diagnostics distinguish discovery, load with verification, reboot and reboot
completion. Load output is bounded to 64 KiB per stream and reported when the
command finishes. Reboot completion is not running-profile identity acceptance:
the companion must reconnect and verify it separately. No write is retried.
Timeout/cancellation during load or reboot leaves device state uncertain and
requires an explicit recovery decision.

Controlled cancellation must write to stdin or close that pipe, then await the
wrapper exit. Cancellation unwinds the running invocation, terminates and reaps
its direct picotool child, and only then exits the wrapper. Killing the wrapper
alone is outside this contract. No descendant tree is expected from the pinned
picotool executable. POSIX cleanup compensates for Zig 0.17.0's canceled
`Threaded.childWaitPosix` clearing the PID before reap; only that PID is restored
for cleanup, since wait already closed its pipes. Offline native tests check
that the recorded child PID no longer exists after timeout or controlled exit,
including children which closed their output pipes. Windows/Linux native
execution and actual USB/driver behavior remain separate acceptance gates.
