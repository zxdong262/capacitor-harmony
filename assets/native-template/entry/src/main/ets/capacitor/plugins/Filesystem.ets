import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { CapacitorPlugin } from '../CapacitorPlugin';
import { PluginCall } from '../PluginCall';

/**
 * `@capacitor/filesystem` — files in the app sandbox.
 *
 * Uses the app's own directories (`filesDir`, `cacheDir`), so no runtime
 * permission is required.  `downloadFile`/`uploadFile` are intentionally left
 * unimplemented in the first edition.
 */
export class FilesystemPlugin extends CapacitorPlugin {
  getPluginId(): string {
    return 'Filesystem';
  }

  getMethods(): string[] {
    return [
      'readFile',
      'writeFile',
      'appendFile',
      'deleteFile',
      'mkdir',
      'rmdir',
      'readdir',
      'stat',
      'getUri',
      'rename',
      'copy',
      'checkPermissions',
      'requestPermissions',
      'downloadFile',
      'uploadFile',
    ];
  }

  readFile(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    const encoding: string = call.getString('encoding', 'utf8');
    try {
      if (!this.exists(path)) {
        call.reject(`File does not exist: ${path}`, 'NOT_EXISTS');
        return;
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(path).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      if (encoding === 'base64') {
        const helper: util.Base64Helper = new util.Base64Helper();
        call.resolve({ data: helper.encodeToStringSync(new Uint8Array(buffer)) } as Object);
      } else {
        const text: string = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buffer));
        call.resolve({ data: text } as Object);
      }
    } catch (e) {
      call.reject(`readFile failed: ${String(e)}`);
    }
  }

  writeFile(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    const recursive: boolean = call.getBoolean('recursive', false);
    const bytes: Uint8Array | null = this.encode(call.getString('data'), call.getString('encoding', 'utf8'));
    if (bytes === null) {
      call.reject('invalid data');
      return;
    }
    try {
      if (!this.ensureParent(path, recursive)) {
        call.reject(`cannot create directory for ${path}`);
        return;
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      fs.closeSync(file);
      call.resolve();
    } catch (e) {
      call.reject(`writeFile failed: ${String(e)}`);
    }
  }

  appendFile(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    const recursive: boolean = call.getBoolean('recursive', false);
    const bytes: Uint8Array | null = this.encode(call.getString('data'), call.getString('encoding', 'utf8'));
    if (bytes === null) {
      call.reject('invalid data');
      return;
    }
    try {
      if (!this.ensureParent(path, recursive)) {
        call.reject(`cannot create directory for ${path}`);
        return;
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      fs.closeSync(file);
      call.resolve();
    } catch (e) {
      call.reject(`appendFile failed: ${String(e)}`);
    }
  }

  deleteFile(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    try {
      if (!this.exists(path)) {
        call.reject(`File does not exist: ${path}`, 'NOT_EXISTS');
        return;
      }
      fs.unlinkSync(path);
      call.resolve();
    } catch (e) {
      call.reject(`deleteFile failed: ${String(e)}`);
    }
  }

  mkdir(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    const recursive: boolean = call.getBoolean('recursive', false);
    try {
      fs.mkdirSync(path, recursive);
      call.resolve();
    } catch (e) {
      call.reject(`mkdir failed: ${String(e)}`);
    }
  }

  rmdir(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    const recursive: boolean = call.getBoolean('recursive', false);
    try {
      if (!fs.statSync(path).isDirectory()) {
        call.reject(`${path} is not a directory`);
        return;
      }
      fs.rmdirSync(path, recursive);
      call.resolve();
    } catch (e) {
      call.reject(`rmdir failed: ${String(e)}`);
    }
  }

  readdir(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    try {
      if (!fs.statSync(path).isDirectory()) {
        call.reject(`${path} is not a directory`);
        return;
      }
      const entries: string[] = fs.listFileSync(path);
      call.resolve({ files: entries } as Object);
    } catch (e) {
      call.reject(`readdir failed: ${String(e)}`);
    }
  }

  stat(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    try {
      const st: fs.Stat = fs.statSync(path);
      call.resolve({
        type: st.isDirectory() ? 'directory' : 'file',
        size: st.size,
        ctime: st.ctime,
        mtime: st.mtime,
        uri: `file://${path}`,
      } as Object);
    } catch (e) {
      call.reject(`stat failed: ${String(e)}`, 'NOT_EXISTS');
    }
  }

  getUri(call: PluginCall): void {
    const path: string = this.resolvePath(call.getString('directory'), call.getString('path'));
    call.resolve({ uri: `file://${path}` } as Object);
  }

  rename(call: PluginCall): void {
    const from: string = this.resolvePath(call.getString('directory'), call.getString('from'));
    const to: string = this.resolvePath(call.getString('directory'), call.getString('to'));
    try {
      fs.renameSync(from, to);
      call.resolve();
    } catch (e) {
      call.reject(`rename failed: ${String(e)}`);
    }
  }

  copy(call: PluginCall): void {
    const from: string = this.resolvePath(call.getString('directory'), call.getString('from'));
    const to: string = this.resolvePath(call.getString('directory'), call.getString('to'));
    try {
      if (!this.exists(from)) {
        call.reject(`source does not exist: ${from}`, 'NOT_EXISTS');
        return;
      }
      if (!this.ensureParent(to, true)) {
        call.reject(`cannot create directory for ${to}`);
        return;
      }
      const src: fs.File = fs.openSync(from, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(from).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(src.fd, buffer);
      fs.closeSync(src);
      const dst: fs.File = fs.openSync(to, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(dst.fd, buffer);
      fs.closeSync(dst);
      call.resolve();
    } catch (e) {
      call.reject(`copy failed: ${String(e)}`);
    }
  }

  checkPermissions(call: PluginCall): void {
    call.resolve({ publicStorage: 'granted' } as Object);
  }

  requestPermissions(call: PluginCall): void {
    call.resolve({ publicStorage: 'granted' } as Object);
  }

  downloadFile(call: PluginCall): void {
    call.unimplemented('downloadFile is not implemented on HarmonyOS yet');
  }

  uploadFile(call: PluginCall): void {
    call.unimplemented('uploadFile is not implemented on HarmonyOS yet');
  }

  // -----------------------------------------------------------------

  private encode(data: string, encoding: string): Uint8Array | null {
    try {
      if (encoding === 'base64') {
        const helper: util.Base64Helper = new util.Base64Helper();
        return helper.decodeSync(data);
      }
      return new util.TextEncoder().encodeInto(data);
    } catch (e) {
      return null;
    }
  }

  private exists(path: string): boolean {
    try {
      fs.accessSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  private ensureParent(path: string, recursive: boolean): boolean {
    const lastSlash: number = path.lastIndexOf('/');
    if (lastSlash <= 0) {
      return true;
    }
    const dir: string = path.substring(0, lastSlash);
    if (this.exists(dir)) {
      return true;
    }
    if (!recursive) {
      return false;
    }
    try {
      fs.mkdirSync(dir, true);
      return true;
    } catch (e) {
      return false;
    }
  }

  private resolvePath(directory: string, path: string): string {
    if (path.length === 0) {
      return this.directoryRoot(directory);
    }
    // Absolute paths ignore `directory`, mirroring the other platforms.
    if (path.startsWith('/')) {
      return path;
    }
    const cleaned: string = path.startsWith('./') ? path.substring(2) : path;
    return `${this.directoryRoot(directory)}/${cleaned}`;
  }

  private directoryRoot(directory: string): string {
    switch (directory) {
      case 'DOCUMENTS':
        return `${this.context.filesDir}/documents`;
      case 'LIBRARY':
        return `${this.context.filesDir}/library`;
      case 'CACHE':
        return this.context.cacheDir;
      case 'EXTERNAL':
      case 'EXTERNAL_STORAGE':
        return `${this.context.filesDir}/external`;
      case 'DATA':
      default:
        return this.context.filesDir;
    }
  }
}
