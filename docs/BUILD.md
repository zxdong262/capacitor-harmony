# Building & running

This document covers the HarmonyOS side: getting the embedded-Node artifacts
ready and producing a runnable `.hap`.

> The adapter CLI (`npx cap add/copy/sync harmony`) runs on **Node ≥ 18** and
> only produces the `harmony/` native project. The HAP itself is built by the
> **HarmonyOS SDK** (DevEco Studio or the command-line `hvigorw`). This package
> does not compile ArkTS or C++ — that happens in the HarmonyOS toolchain.

---

## 1. Prerequisites

| Requirement | Notes |
|-------------|-------|
| Node.js ≥ 18 | For the adapter CLI and `hvigor`. |
| HarmonyOS SDK (command-line) | API 12+. Provides `hvigorw` and the NDK. |
| A signing config | `build-profile.json5` (or pass via `-p signingConfig=...`). |
| `curl` + `python3` | Used by `scripts/prepare-node.sh` for download + ELF checks. |
| `libnode.so` | Downloaded by the prepare script (NOT committed). |

You also need a Huawei developer device (arm64) or the emulator (x64), with
USB/network access for `hdc install`.

---

## 2. Generate the native project

From your Capacitor app:

```bash
npm install capacitor-harmony @capacitor/core @capacitor/cli
npx cap add harmony          # scaffold harmony/ from the template
npx cap sync harmony         # copy www/node, write config, regenerate registry
```

`npx cap sync harmony` produces everything under `harmony/` except the
`libnode.so` binary and the compiled `libcapacitor_node.so`.

---

## 3. Fetch the embedded Node binary

```bash
# device (arm64-v8a) — the default
./scripts/prepare-node.sh arm64

# emulator / x86_64
./scripts/prepare-node.sh x64
```

What it does:

1. Downloads `libnode-{arm64,x64}.so` from the
   `electerm/ohos-node-shared@ohos-node-shared-v24.2.0` release.
2. Verifies the **SHA-256** against a pinned hash
   (`arm64`: `3019bf5f…71151a1`, `x64`: `d001ec8b…3608990`).
3. Rejects **PIE** artifacts (parses the ELF header in Python — a valid
   `--shared` `.so` must be `ET_DYN` with no `PT_INTERP`). A PIE build would
   crash inside V8.
4. Copies the file to `entry/libs/<abi>/libnode.so`.

The C++ headers are fetched separately (used by the NDK to compile
`libcapacitor_node.so`):

```bash
./scripts/prepare-headers.sh   # downloads node v24.2.0 headers → entry/node-headers/include
```

---

## 4. Build the HAP

All-in-one:

```bash
./scripts/build-hap.sh arm64     # or: ./scripts/build-hap.sh x64
```

This runs the two prepare scripts, then:

```bash
./hvigorw assembleHap --mode module \
  -p module=entry@default -p product=default --analyze=normal
```

If `hvigorw` is not on your PATH, open the `harmony/` project in DevEco Studio
and build the `entry` module, or run the `hvigorw` command above from
`harmony/`.

> The first build compiles `libcapacitor_node.cpp` (the NAPI glue) and links it
> against `libnode.so` from `entry/libs/<abi>/`. It needs
> `entry/node-headers/include` (step 3) and the OHOS NDK on PATH.

---

## 5. Install & run

```bash
hdc install harmony/entry/build/default/outputs/default/entry-default-signed.hap
# launch from the device, or:
hdc shell aa start -a EntryAbility -b <your.bundle.name>
```

On first launch the app extracts `rawfile/node/**` into the writable
`filesDir/node` (because `require()`/`fs` need a real path), then — if
`harmony.autostartNode` is not `false` — starts the Node runtime automatically.

---

## 6. Pointing the WebView at a dev server

During development you can skip the asset server and load your dev server
directly. Set in `capacitor.config.ts`:

```ts
harmony: {
  serverUrl: 'http://10.0.2.2:5173/',   // your dev server, reachable from the device
}
```

(re)run `npx cap sync harmony` so the new `serverUrl` lands in
`rawfile/capacitor.config.json`, rebuild, reinstall.

---

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `failed to start node — is libnode.so present?` | `libnode.so` missing in `entry/libs/<abi>/` | Re-run `prepare-node.sh <abi>`. |
| App crashes on Node start (`IsAllowed` assertion) | A **PIE** `libnode.so` slipped in | The prepare script blocks this; re-download from the official release. |
| `nodeEntry` not found | `node/main.js` not under `webDir`'s `node/` | Make sure `node/` is copied into `rawfile/node` (it is part of `cap sync`). |
| WebView blank | `http://localhost/` not served / asset server not intercepting | Check `server.url` and that `bridge.js` is injected; enable `logging: true`. |
| `libcapacitor_node.so` link errors | node headers missing | Re-run `prepare-headers.sh`; confirm `entry/node-headers/include/node/node.h` exists. |

---

## 8. Footprint notes

- `entry/libs/`, `entry/node-headers/`, `oh_modules/`, `build/`, `harmony/` are
  git-ignored (see `.gitignore`). They are generated/downloaded, not source.
- The template's `startIcon.png` is a placeholder solid-blue asset. Replace
  `entry/src/main/resources/base/media/startIcon.png` with your real icon
  before publishing.
