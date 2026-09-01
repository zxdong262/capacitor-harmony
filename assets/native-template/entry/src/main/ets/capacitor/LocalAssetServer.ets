import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';

const TAG: string = 'LocalAssetServer';
const DOMAIN: number = 0x0000;

/** Prefix we serve local web assets from. */
export const LOCAL_SERVER_ORIGIN: string = 'http://localhost';
/** Where the injected bridge script is reachable from inside the WebView. */
export const BRIDGE_SCRIPT_URL: string = '/__capacitor/bridge.js';
const BRIDGE_RAWFILE: string = '__capacitor/bridge.js';
const HEADERS_TOKEN: string = '__CAPACITOR_PLUGIN_HEADERS__';
/** `Capacitor.convertFileSrc()` maps `file:///a/b` to this prefix. */
const FILE_SRC_PREFIX: string = '_capacitor_file_/';

/**
 * Serves the web app out of the HAP's `rawfile/www` over a virtual
 * `http://localhost/` origin.
 *
 * Why not `file://`?  ArkWeb enforces a strict origin policy on `file://`:
 * `fetch()`, cookies, service workers and ES modules all break.  Capacitor on
 * Android solves this with `WebViewLocalServer`; here we use ArkWeb's
 * `onInterceptRequest()`, which is the same trick with less code.
 */
export class LocalAssetServer {
  private context: common.UIAbilityContext;
  private bridgeSource: string = '';

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * Build the `WebResourceResponse` for a request, or `null` to let ArkWeb
   * handle it normally (remote URLs, dev servers, ...).
   */
  handleRequest(url: string, pluginHeadersJson: string): WebResourceResponse | null {
    if (!url.startsWith(`${LOCAL_SERVER_ORIGIN}/`)) {
      return null;
    }

    // The bridge script is generated on the fly because it embeds the plugin
    // registry.
    if (url === `${LOCAL_SERVER_ORIGIN}${BRIDGE_SCRIPT_URL}`) {
      return this.textResponse(this.getBridgeSource(pluginHeadersJson), 'application/javascript');
    }

    let path: string = decodeURIComponent(url.substring(LOCAL_SERVER_ORIGIN.length + 1));
    const queryIndex: number = path.search(/[?#]/);
    if (queryIndex >= 0) {
      path = path.substring(0, queryIndex);
    }
    if (path.length === 0 || path.endsWith('/')) {
      path += 'index.html';
    }
    // Path traversal guard — rawfile is not a filesystem, but be explicit.
    if (path.includes('..')) {
      return this.emptyResponse(403, 'Forbidden');
    }

    // Real files on disk, exposed through Capacitor.convertFileSrc().
    if (path.startsWith(FILE_SRC_PREFIX)) {
      return this.serveFileSystem(`/${path.substring(FILE_SRC_PREFIX.length)}`);
    }

    const bytes: Uint8Array | null = this.readRawFile(`www/${path}`);
    if (bytes === null) {
      // SPA fallback: unknown paths without an extension serve index.html.
      if (!path.includes('.')) {
        const index: Uint8Array | null = this.readRawFile('www/index.html');
        if (index !== null) {
          return this.response(index, 'text/html');
        }
      }
      hilog.warn(DOMAIN, TAG, '404 %{public}s', path);
      return this.emptyResponse(404, 'Not Found');
    }

    if (path === 'index.html' || path.endsWith('/index.html')) {
      return this.response(this.injectBridge(bytes, pluginHeadersJson), 'text/html');
    }
    return this.response(bytes, this.getMimeType(path));
  }

  /** Inject `<script src="/__capacitor/bridge.js">` as the first thing in <head>. */
  private injectBridge(html: Uint8Array, pluginHeadersJson: string): Uint8Array {
    // Serve the bridge inline: one less request, and it is guaranteed to run
    // before every other script in the document.
    const source: string = this.getBridgeSource(pluginHeadersJson);
    const tag: string = `<script>${source}</script>`;
    let text: string = new util.TextDecoder('utf-8').decodeToString(html);
    const headIndex: number = text.search(/<head[^>]*>/i);
    if (headIndex >= 0) {
      const end: number = text.indexOf('>', headIndex) + 1;
      text = text.substring(0, end) + tag + text.substring(end);
    } else {
      text = tag + text;
    }
    return new util.TextEncoder().encodeInto(text);
  }

  private getBridgeSource(pluginHeadersJson: string): string {
    if (this.bridgeSource.length > 0) {
      return this.bridgeSource.replace(HEADERS_TOKEN, pluginHeadersJson);
    }
    const raw: Uint8Array | null = this.readRawFile(BRIDGE_RAWFILE);
    if (raw === null) {
      hilog.error(DOMAIN, TAG, 'rawfile/%{public}s is missing — the bridge cannot start', BRIDGE_RAWFILE);
      return 'console.error("[capacitor-harmony] bridge script missing");';
    }
    this.bridgeSource = new util.TextDecoder('utf-8').decodeToString(raw);
    return this.bridgeSource.replace(HEADERS_TOKEN, pluginHeadersJson);
  }

  /** Serve a real file from the device filesystem (filesDir, cacheDir, ...). */
  private serveFileSystem(absolutePath: string): WebResourceResponse {
    try {
      const file: fs.File = fs.openSync(absolutePath, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(absolutePath).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      return this.response(new Uint8Array(buffer), this.getMimeType(absolutePath));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'cannot read %{public}s: %{public}s', absolutePath, String(e));
      return this.emptyResponse(404, 'Not Found');
    }
  }

  private readRawFile(path: string): Uint8Array | null {
    try {
      return this.context.resourceManager.getRawFileContentSync(path);
    } catch (e) {
      return null;
    }
  }

  private response(bytes: Uint8Array, mimeType: string): WebResourceResponse {
    const response: WebResourceResponse = new WebResourceResponse();
    const buffer: ArrayBuffer = bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    ) as ArrayBuffer;
    response.setResponseData(buffer);
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType(mimeType);
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    response.setResponseHeader([{ headerKey: 'Access-Control-Allow-Origin', headerValue: '*' }]);
    return response;
  }

  private textResponse(text: string, mimeType: string): WebResourceResponse {
    return this.response(new util.TextEncoder().encodeInto(text), mimeType);
  }

  private emptyResponse(code: number, reason: string): WebResourceResponse {
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseCode(code);
    response.setReasonMessage(reason);
    response.setResponseData(new ArrayBuffer(0));
    response.setResponseMimeType('text/plain');
    return response;
  }

  private getMimeType(path: string): string {
    const lower: string = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'text/html';
    }
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return 'application/javascript';
    }
    if (lower.endsWith('.cjs')) {
      return 'application/javascript';
    }
    if (lower.endsWith('.css')) {
      return 'text/css';
    }
    if (lower.endsWith('.json')) {
      return 'application/json';
    }
    if (lower.endsWith('.map')) {
      return 'application/json';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.svg')) {
      return 'image/svg+xml';
    }
    if (lower.endsWith('.ico')) {
      return 'image/x-icon';
    }
    if (lower.endsWith('.wasm')) {
      return 'application/wasm';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.woff')) {
      return 'font/woff';
    }
    if (lower.endsWith('.woff2')) {
      return 'font/woff2';
    }
    if (lower.endsWith('.ttf')) {
      return 'font/ttf';
    }
    if (lower.endsWith('.otf')) {
      return 'font/otf';
    }
    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.webm')) {
      return 'video/webm';
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return 'text/plain';
    }
    return 'application/octet-stream';
  }
}
