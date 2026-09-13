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
npm install harmony@npm:capacitor-harmony @capacitor/core @capacitor/cli
npx cap add harmony          # scaffold harmony/ from the template
npx cap sync harmony         # copy www/node, write config, regenerate registry
```

> `npx cap <cmd> harmony` resolves the platform through
> `node_modules/harmony/package.json`, so the package must be installed under
> the `harmony` alias (or `harmony@file:...` for a local checkout).

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
3. Sanity-checks the ELF header in Python — a valid `--shared` `.so` must be
   `ET_DYN`. A wrong-type artifact would crash inside V8.
4. Copies the file to `entry/libs/<abi>/libnode.so`.

> **No Node.js headers are needed.** `libcapacitor_node.so` does not compile
> against `libnode.so` — it `dlopen()`s it at runtime from the app's lib dir
> (linking it would record `DT_NEEDED libnode.so.137`, its SONAME, which can
> never be resolved because the shipped file is named `libnode.so`).

---

## 4. Build the HAP

All-in-one (run from your app root — `scripts/` here means
`harmony/scripts/`, copied in by `npx cap add harmony`):

```bash
./harmony/scripts/build-hap.sh arm64     # or: ./harmony/scripts/build-hap.sh x64
```

This runs the prepare script, then `hvigorw assembleHap` (falling back to
`hvigorw` on your PATH — e.g. DevEco's
`Contents/tools/hvigor/bin` — when the project has no wrapper of its own).

If `hvigorw` is not on your PATH, open the `harmony/` project in DevEco Studio
and build the `entry` module, or from `harmony/` run:

```bash
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

> The first build compiles `libcapacitor_node.cpp` + `node_embed.cpp` into
> `libcapacitor_node.so` (needs only the OHOS NDK). `libnode.so` is loaded at
> runtime with `dlopen()` — never linked — and must be present in
> `entry/libs/<abi>/` so hvigor packs it into the HAP.

---

## 5. Install & run

```bash
# debug build → entry-default-unsigned.hap (installs on the emulator;
# real devices need a signed HAP — see §8 / your provision profile)
hdc install harmony/entry/build/default/outputs/default/entry-default-unsigned.hap
# launch from the device, or:
hdc shell aa start -a EntryAbility -b <your.bundle.name>
```

### Emulator (x86_64)

1. Build the x64 variant: `./harmony/scripts/prepare-node.sh x64` first (the
   template compiles `libcapacitor_node.so` for `arm64-v8a` + `x86_64`, but the
   prebuilt `libnode.so` must be present per ABI you ship).
2. If no emulator image is installed yet, open DevEco Studio → Device Manager,
   sign in with your Huawei developer account, and download a Phone image.
   Headless installs are not supported — this step needs the IDE.
3. Start the emulator, then verify it is visible:
   ```bash
   hdc list targets     # should list one device, not `[Empty]`
   ```
4. `hdc install …` / `aa start …` as above. Watch the backend boot:
   ```bash
   hdc hilog | grep -i -E "capacitor|node_embed|demo"
   ```
   A working app shows `node backend listening on http://127.0.0.1:3000` and
   the WebView answers `Node.callApi('/api/hello')` with `{ok:true,…}`.

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
| `libcapacitor_node.so` link errors | OHOS NDK / sysroot not on PATH | Install the HarmonyOS native SDK; no Node headers are needed (libnode is dlopen'd at runtime). |
| `node: stopped` + `node-boot.log` says `dlopen("…libnode.so") failed` | `libnode.so` not packaged into the HAP | Re-run `prepare-node.sh <abi>`; check `entry/libs/<abi>/libnode.so` exists and `collectAllLibs` didn't filter it out. |
| `node: stopped` + log shows `node::Start returned rc=…` right away | backend entry crashed/exited | Read the `[demo]`/node stack lines above it in `node-boot.log` (shown by `Node.getLog`). |

---

## 8. Footprint notes

- `entry/libs/`, `oh_modules/`, `build/`, `harmony/` are
  git-ignored (see `.gitignore`). They are generated/downloaded, not source.
- The template's `startIcon.png` is a placeholder solid-blue asset. Replace
  `entry/src/main/resources/base/media/startIcon.png` with your real icon
  before publishing.
