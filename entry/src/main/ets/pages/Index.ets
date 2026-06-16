import web_webview from '@ohos.web.webview';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import router from '@ohos.router';
import { BusinessError } from '@ohos.base';

// ── Helpers ──────────────────────────────────────────────────────────

function escapeForJS(s: string): string {
  return s.replace(/\\/g, '\\\\')
          .replace(/'/g, "\\'")
          .replace(/\n/g, '\\n')
          .replace(/\r/g, '\\r');
}

function uint8ArrayToBase64(data: Uint8Array): string {
  let helper = new util.Base64Helper();
  return helper.encodeToStringSync(data);
}

function base64ToUint8Array(b64: string): Uint8Array {
  let helper = new util.Base64Helper();
  return helper.decodeSync(b64);
}

// ── Bridge ───────────────────────────────────────────────────────────

class NativeBridge {
  private controller: web_webview.WebviewController;

  constructor(ctrl: web_webview.WebviewController) {
    this.controller = ctrl;
  }

  /**
   * Called from JS: ohosWebView.callNative(handler, data, callbackId)
   *   handler   – 'openFile' | 'saveFile'
   *   data      – JSON string with parameters
   *   callbackId – unique string; native must call _nativeCallback(id, err, result)
   */
  callNative(handler: string, data: string, callbackId: string): void {
    console.info('[PanguBridge] callNative handler=' + handler + ' cb=' + callbackId);

    try {
      switch (handler) {
        case 'openFile':
          this.handleOpenFile(callbackId);
          break;
        case 'saveFile':
          this.handleSaveFile(data, callbackId);
          break;
        default:
          this.reject(callbackId, 'Unknown handler: ' + handler);
      }
    } catch (e) {
      this.reject(callbackId, 'Native error: ' + (e as Error).message);
    }
  }

  /** JS → open file picker → read file → return base64-encoded content */
  private handleOpenFile(callbackId: string): void {
    let documentSelectOptions = new picker.DocumentSelectOptions();
    documentSelectOptions.maxSelectNumber = 1;

    let documentPicker = new picker.DocumentViewPicker();
    documentPicker.select(documentSelectOptions)
      .then((uris: string[]) => {
        if (!uris || uris.length === 0) {
          this.reject(callbackId, 'User cancelled');
          return;
        }
        let uri = uris[0];
        console.info('[PanguBridge] openFile selected: ' + uri);
        this.readFileAndResolve(uri, callbackId);
      })
      .catch((err: BusinessError) => {
        console.error('[PanguBridge] picker error: ' + err.message);
        this.reject(callbackId, 'Picker error: ' + err.message);
      });
  }

  private readFileAndResolve(uri: string, callbackId: string): void {
    try {
      let file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let stat: fs.Stat = fs.statSync(file.fd);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      let base64 = uint8ArrayToBase64(new Uint8Array(buf));
      let fileName = uri.substring(uri.lastIndexOf('/') + 1);
      let result = JSON.stringify({
        name: fileName,
        size: stat.size,
        data: base64
      });
      this.resolve(callbackId, result);
    } catch (e) {
      this.reject(callbackId, 'Read error: ' + (e as Error).message);
    }
  }

  /** JS → parse data → save file picker → write decoded data */
  private handleSaveFile(dataStr: string, callbackId: string): void {
    let params: Record<string, string>;
    try {
      params = JSON.parse(dataStr) as Record<string, string>;
    } catch (e) {
      this.reject(callbackId, 'Invalid JSON data');
      return;
    }

    let name: string = params['name'] || 'plasmid.gb';
    let b64Data: string = params['data'] || '';
    if (!b64Data) {
      this.reject(callbackId, 'No data to save');
      return;
    }

    let saveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [name];

    let documentPicker = new picker.DocumentViewPicker();
    documentPicker.save(saveOptions)
      .then((uris: string[]) => {
        if (!uris || uris.length === 0) {
          this.reject(callbackId, 'User cancelled save');
          return;
        }
        let uri = uris[0];
        console.info('[PanguBridge] saveFile to: ' + uri);
        this.writeFile(uri, b64Data, callbackId);
      })
      .catch((err: BusinessError) => {
        this.reject(callbackId, 'Save picker error: ' + err.message);
      });
  }

  private writeFile(uri: string, b64Data: string, callbackId: string): void {
    try {
      let decoded = base64ToUint8Array(b64Data);
      let file: fs.File = fs.openSync(uri,
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, decoded.buffer);
      fs.closeSync(file);
      this.resolve(callbackId, JSON.stringify({ success: true }));
    } catch (e) {
      this.reject(callbackId, 'Write error: ' + (e as Error).message);
    }
  }

  // ── callback helpers ───────────────────────────────────────────

  private resolve(callbackId: string, resultJson: string): void {
    let safe = escapeForJS(resultJson);
    let js = `_nativeCallback('${callbackId}', null, '${safe}')`;
    this.runJS(js);
  }

  private reject(callbackId: string, errorMsg: string): void {
    let safe = escapeForJS(errorMsg);
    let js = `_nativeCallback('${callbackId}', '${safe}', null)`;
    this.runJS(js);
  }

  private runJS(script: string): void {
    this.controller.runJavaScript(script)
      .catch((e: BusinessError) => {
        console.error('[PanguBridge] runJavaScript failed: ' + e.message);
      });
  }
}

// ── Page ─────────────────────────────────────────────────────────────

@Entry
@Component
struct Index {
  controller: web_webview.WebviewController = new web_webview.WebviewController();
  bridge: NativeBridge = new NativeBridge(this.controller);

  onBackPress(): boolean {
    this.checkDirtyAndClose();
    return true; // intercept back press
  }

  async checkDirtyAndClose() {
    try {
      let result = await this.controller.runJavaScript('window.isDirty||false');
      let dirty = result === 'true';
      if (dirty) {
        AlertDialog.show({
          title: '未保存的修改',
          message: '文件已修改，是否在关闭前保存？',
          autoCancel: true,
          alignment: DialogAlignment.Center,
          primaryButton: {
            value: '保存并关闭',
            fontColor: '#4f8cff',
            action: () => {
              this.controller.runJavaScript('saveAs(lastSaveFormat)')
                .then(() => {
                  setTimeout(() => { router.back(); }, 300);
                })
                .catch(() => { router.back(); });
            }
          },
          secondaryButton: {
            value: '不保存',
            fontColor: '#e05050',
            action: () => {
              router.back();
            }
          },
          cancel: () => {
            // 取消 — 留在页面
          }
        });
      } else {
        router.back();
      }
    } catch (e) {
      router.back();
    }
  }

  build() {
    Column() {
      Web({ src: $rawfile('v2.html'), controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .fileAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: 'ohosWebView',
          methodList: ['callNative'],
          controller: this.controller
        })
        .onErrorReceive((event) => {
          console.error('[GenePen] Error: ' + (event?.error?.getErrorInfo?.() ?? 'unknown'));
        })
        .onPageEnd(() => {
          console.info('[GenePen] Page loaded');
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0d1117')
  }
}