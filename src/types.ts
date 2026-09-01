/**
 * Types shared by the `capacitor-harmony` CLI hooks.
 *
 * The Capacitor CLI invokes us with `CAPACITOR_CONFIG` (JSON of the user
 * `capacitor.config.[ts|json]` "external" config) plus `CAPACITOR_ROOT_DIR`
 * and `CAPACITOR_WEB_DIR`.  We deliberately do not depend on `@capacitor/cli`
 * types so the package stays small and version agnostic.
 */

/** HarmonyOS specific section of `capacitor.config.*`. */
export interface HarmonyPlatformConfig {
  /**
   * Directory (relative to the app root) holding the Node.js backend that
   * should be bundled and executed inside the app by the embedded
   * `libnode.so` runtime.  Defaults to `node`.
   *
   * Set to `false` to ship without a Node backend (the native `.so` is then
   * not required at build time).
   */
  nodeDir?: string | false;

  /** Entry file inside {@link HarmonyPlatformConfig.nodeDir}. Default `main.js`. */
  nodeEntry?: string;

  /**
   * Start the embedded Node runtime automatically when the app launches.
   * Default `true` when a `nodeDir` is present.
   */
  autostartNode?: boolean;

  /**
   * Override the URL the WebView loads.
   *
   * Default is the built-in local asset server (`http://localhost/`).  Point
   * this at your Node backend (e.g. `http://127.0.0.1:3000/`) to render the
   * UI straight from Node — the same model electerm-harmony uses.
   */
  serverUrl?: string;

  /** Override the HarmonyOS bundle name (defaults to `appId`). */
  bundleName?: string;

  /** Override the HarmonyOS app label (defaults to `appName`). */
  appLabel?: string;

  /** Device types declared in `module.json5`. Default `["2in1", "tablet", "phone"]`. */
  deviceTypes?: string[];

  /** Extra user-grant permissions to request at startup. */
  permissions?: string[];

  /**
   * Signing config directory.  When set, `scripts/build-hap.sh` will attempt
   * to sign the produced `.app`.
   */
  signing?: string;
}

/** The subset of the Capacitor config we consume. */
export interface CapacitorConfig {
  appId?: string;
  appName?: string;
  webDir?: string;
  bundledWebRuntime?: boolean;
  server?: {
    url?: string;
    cleartext?: boolean;
    [key: string]: any;
  };
  harmony?: HarmonyPlatformConfig;
  plugins?: Record<string, any>;
  [key: string]: any;
}
