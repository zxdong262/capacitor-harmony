/*!
 * capacitor-harmony — native bridge (WebView side)
 *
 * This file is bundled in the HAP under `rawfile/__capacitor/bridge.js`.
 * The local asset server injects it as the first script of the served
 * `index.html`, so it is guaranteed to run before the web app's bundle.
 *
 * It is a port of `core/native-bridge.ts` from ionic-team/capacitor, adapted
 * to HarmonyOS:
 *   - JS -> native  : window.harmonyBridge.postMessage(JSON string)
 *     (ArkWeb `javaScriptProxy`)
 *   - native -> JS  : window.Capacitor.fromNative(obj)
 *     (ArkWeb `runJavaScript`)
 *
 * `window.CapacitorCustomPlatform` is declared here (before `@capacitor/core`
 * is imported) because `createCapacitor()` captures it at module init time —
 * that is what makes `Capacitor.getPlatform()` return `harmony`.
 */
(function (win) {
  'use strict';

  if (win.Capacitor && win.Capacitor.__harmonyBridgeInstalled === true) {
    return;
  }

  // ---------------------------------------------------------------------
  // Platform identity.  Must be set before @capacitor/core loads.
  // ---------------------------------------------------------------------
  win.CapacitorCustomPlatform = { name: 'harmony', plugins: {} };

  // Origin the local asset server serves the web app from.  Used by
  // `Capacitor.convertFileSrc()` and by the CapacitorHttp proxy.
  var WEBVIEW_SERVER_URL = win.WEBVIEW_SERVER_URL || 'http://localhost';
  win.WEBVIEW_SERVER_URL = WEBVIEW_SERVER_URL;

  var cap = win.Capacitor || (win.Capacitor = {});
  cap.Plugins = cap.Plugins || {};
  // `__CAPACITOR_PLUGIN_HEADERS__` is replaced with a JSON literal by the
  // native side before this file is handed to the WebView.
  cap.PluginHeaders = win.__CAPACITOR_PLUGIN_HEADERS__ || [];
  cap.__harmonyBridgeInstalled = true;

  // `cap.Exception` is normally installed by @capacitor/core; provide a local
  // fallback so results arriving before the app bundle loads still work.
  if (!cap.Exception) {
    cap.Exception = function CapacitorException(message, code, data) {
      var err = Error.call(this, message);
      this.message = message;
      this.code = code;
      this.data = data;
      this.stack = err.stack;
      return this;
    };
    cap.Exception.prototype = Object.create(Error.prototype);
    cap.Exception.prototype.constructor = cap.Exception;
  }

  // ---------------------------------------------------------------------
  // Call plumbing
  // ---------------------------------------------------------------------
  var callbacks = new Map();
  var callbackIdCount = Math.floor(Math.random() * 134217728);

  function postToNative(data) {
    try {
      if (win.harmonyBridge && typeof win.harmonyBridge.postMessage === 'function') {
        win.harmonyBridge.postMessage(JSON.stringify(data));
      } else {
        win.console && win.console.warn('[capacitor-harmony] harmonyBridge proxy missing');
      }
    } catch (e) {
      win.console && win.console.error(e);
    }
  }

  function convertFileSrcServerUrl(webviewServerUrl, filePath) {
    if (typeof filePath === 'string') {
      if (filePath.indexOf('/') === 0) {
        return webviewServerUrl + '/_capacitor_file_' + filePath;
      } else if (filePath.indexOf('file://') === 0) {
        return webviewServerUrl + filePath.replace('file://', '/_capacitor_file_');
      }
    }
    return filePath;
  }

  cap.getServerUrl = function () {
    return WEBVIEW_SERVER_URL;
  };

  cap.convertFileSrc = function (filePath) {
    return convertFileSrcServerUrl(WEBVIEW_SERVER_URL, filePath);
  };

  cap.getPlatform = function () {
    return 'harmony';
  };

  cap.isNativePlatform = function () {
    return true;
  };

  cap.isPluginAvailable = function (name) {
    if (Object.prototype.hasOwnProperty.call(cap.Plugins, name)) {
      return true;
    }
    var headers = cap.PluginHeaders || [];
    for (var i = 0; i < headers.length; i++) {
      if (headers[i].name === name) {
        return true;
      }
    }
    return false;
  };

  // ---------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------
  var BRIDGED_CONSOLE_METHODS = ['debug', 'error', 'info', 'log', 'trace', 'warn'];

  function serializeConsoleMessage(msg) {
    try {
      if (typeof msg === 'object') {
        msg = JSON.stringify(msg);
      }
      return String(msg);
    } catch (e) {
      return '';
    }
  }

  function isFullConsole(c) {
    if (!c) {
      return false;
    }
    return typeof c.groupCollapsed === 'function' || typeof c.groupEnd === 'function';
  }

  cap.logJs = function (msg, level) {
    switch (level) {
      case 'error':
        win.console.error(msg);
        break;
      case 'warn':
        win.console.warn(msg);
        break;
      case 'info':
        win.console.info(msg);
        break;
      default:
        win.console.log(msg);
    }
  };

  cap.logToNative = function (call) {
    var c = win.console;
    if (isFullConsole(c)) {
      c.groupCollapsed(
        '%cnative %c' + call.pluginId + '.' + call.methodName + ' (#' + call.callbackId + ')',
        'font-weight: lighter; color: gray',
        'font-weight: bold; color: #000',
      );
      c.dir(call);
      c.groupEnd();
    } else {
      c.log('LOG TO NATIVE: ', call);
    }
  };

  cap.logFromNative = function (result) {
    var c = win.console;
    if (isFullConsole(c)) {
      var success = result.success === true;
      var tagStyles = success
        ? 'font-style: italic; font-weight: lighter; color: gray'
        : 'font-style: italic; font-weight: lighter; color: red';
      c.groupCollapsed(
        '%cresult %c' + result.pluginId + '.' + result.methodName + ' (#' + result.callbackId + ')',
        tagStyles,
        'font-style: italic; font-weight: bold; color: #444',
      );
      if (success === false) {
        c.error(result.error);
      } else {
        c.dir(JSON.stringify(result.data));
      }
      c.groupEnd();
    } else {
      if (result.success === false) {
        c.error('LOG FROM NATIVE', result.error);
      } else {
        c.log('LOG FROM NATIVE', result.data);
      }
    }
  };

  cap.handleError = function (err) {
    win.console.error(err);
  };

  cap.handleWindowError = function (msg, url, lineNo, columnNo, err) {
    var str = String(msg).toLowerCase();
    if (str.indexOf('script error') > -1) {
      // Ignore cross-origin "Script error." noise.
      return false;
    }
    postToNative({
      type: 'js.error',
      error: {
        message: String(msg),
        url: url,
        line: lineNo,
        col: columnNo,
        errorObject: JSON.stringify(err),
      },
    });
    if (err !== null && err !== undefined) {
      cap.handleError(err);
    }
    return false;
  };

  // Forward console output to the native logger (hilog).  The patch is always
  // installed but only forwards while `Capacitor.isLoggingEnabled` is true, so
  // `capacitor.config.ts` can toggle it at runtime.
  if (win.console) {
    BRIDGED_CONSOLE_METHODS.forEach(function (method) {
      var original = win.console[method];
      if (typeof original !== 'function') {
        return;
      }
      var bound = original.bind(win.console);
      Object.defineProperty(win.console, method, {
        value: function () {
          var msgs = Array.prototype.slice.call(arguments);
          if (cap.isLoggingEnabled === true) {
            cap.toNative('Console', 'log', {
              level: method,
              message: msgs.map(serializeConsoleMessage).join(' '),
            });
          }
          return bound.apply(win.console, msgs);
        },
        configurable: true,
      });
    });
  }

  if (cap.DEBUG === true) {
    win.addEventListener('error', function (e) {
      cap.handleWindowError(e.message, e.filename, e.lineno, e.colno, e.error);
    });
  }

  // ---------------------------------------------------------------------
  // JS -> native
  // ---------------------------------------------------------------------
  cap.toNative = function (pluginName, methodName, options, storedCallback) {
    try {
      var callbackId = '-1';
      if (
        storedCallback &&
        (typeof storedCallback.callback === 'function' || typeof storedCallback.resolve === 'function')
      ) {
        callbackId = String(++callbackIdCount);
        callbacks.set(callbackId, storedCallback);
      }
      var callData = {
        callbackId: callbackId,
        pluginId: pluginName,
        methodName: methodName,
        options: options || {},
      };
      if (cap.isLoggingEnabled === true && pluginName !== 'Console') {
        cap.logToNative(callData);
      }
      postToNative(callData);
      return callbackId;
    } catch (e) {
      win.console && win.console.error(e);
    }
    return null;
  };

  cap.nativeCallback = function (pluginName, methodName, options, callback) {
    if (typeof options === 'function') {
      win.console &&
        win.console.warn("Using a callback as the 'options' parameter of 'nativeCallback()' is deprecated.");
      callback = options;
      options = null;
    }
    return cap.toNative(pluginName, methodName, options, { callback: callback });
  };

  cap.nativePromise = function (pluginName, methodName, options) {
    return new Promise(function (resolve, reject) {
      cap.toNative(pluginName, methodName, options, { resolve: resolve, reject: reject });
    });
  };

  // ---------------------------------------------------------------------
  // native -> JS
  // ---------------------------------------------------------------------
  function returnResult(result) {
    if (cap.isLoggingEnabled === true && result.pluginId !== 'Console') {
      cap.logFromNative(result);
    }
    try {
      var storedCall = callbacks.get(result.callbackId);
      if (storedCall) {
        if (result.error) {
          // Copy the error properties onto a real Error so stacks survive.
          var err = new cap.Exception((result.error && result.error.message) || '');
          for (var key in result.error) {
            if (Object.prototype.hasOwnProperty.call(result.error, key)) {
              err[key] = result.error[key];
            }
          }
          result.error = err;
        }
        if (typeof storedCall.callback === 'function') {
          if (result.success) {
            storedCall.callback(result.data);
          } else {
            storedCall.callback(null, result.error);
          }
        } else if (typeof storedCall.resolve === 'function') {
          if (result.success) {
            storedCall.resolve(result.data);
          } else {
            storedCall.reject(result.error);
          }
          callbacks.delete(result.callbackId);
        }
      } else if (!result.success && result.error) {
        win.console && win.console.warn(result.error);
      }
      if (result.save === false) {
        callbacks.delete(result.callbackId);
      }
    } catch (e) {
      win.console && win.console.error(e);
    }
    delete result.data;
    delete result.error;
  }

  cap.fromNative = function (result) {
    returnResult(result);
  };

  // ---------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------
  cap.addListener = function (pluginName, eventName, callback) {
    var callbackId = cap.nativeCallback(pluginName, 'addListener', { eventName: eventName }, callback);
    return {
      remove: function () {
        win.console && win.console.debug('Removing listener', pluginName, eventName);
        cap.removeListener(pluginName, callbackId, eventName, callback);
      },
    };
  };

  cap.removeListener = function (pluginName, callbackId, eventName, callback) {
    cap.nativeCallback(pluginName, 'removeListener', { callbackId: callbackId, eventName: eventName }, callback);
  };

  cap.createEvent = function (eventName, eventData) {
    var doc = win.document;
    if (doc) {
      var ev = doc.createEvent('Events');
      ev.initEvent(eventName, false, false);
      if (eventData && typeof eventData === 'object') {
        for (var i in eventData) {
          if (Object.prototype.hasOwnProperty.call(eventData, i)) {
            ev[i] = eventData[i];
          }
        }
      }
      return ev;
    }
    return null;
  };

  cap.triggerEvent = function (eventName, target, eventData) {
    var doc = win.document;
    var cordova = win.cordova;
    eventData = eventData || {};
    var ev = cap.createEvent(eventName, eventData);
    if (ev) {
      if (target === 'document') {
        if (cordova && cordova.fireDocumentEvent) {
          cordova.fireDocumentEvent(eventName, eventData);
          return true;
        } else if (doc && doc.dispatchEvent) {
          return doc.dispatchEvent(ev);
        }
      } else if (target === 'window' && win.dispatchEvent) {
        return win.dispatchEvent(ev);
      } else if (doc && doc.querySelector) {
        var targetEl = doc.querySelector(target);
        if (targetEl) {
          return targetEl.dispatchEvent(ev);
        }
      }
    }
    return false;
  };

  // ---------------------------------------------------------------------
  // Legacy / Cordova compatibility shims
  // ---------------------------------------------------------------------
  win.cordova = win.cordova || {};

  if (win.navigator) {
    win.navigator.app = win.navigator.app || {};
    win.navigator.app.exitApp = function () {
      if (!cap.Plugins || !cap.Plugins.App) {
        win.console && win.console.warn('App plugin not installed');
      } else {
        cap.nativeCallback('App', 'exitApp', {});
      }
    };
  }

  if (win.document) {
    var docAddEventListener = win.document.addEventListener;
    win.document.addEventListener = function () {
      var args = Array.prototype.slice.call(arguments);
      var eventName = args[0];
      var handler = args[1];
      if (eventName === 'deviceready' && handler) {
        Promise.resolve().then(handler);
      } else if (eventName === 'backbutton' && cap.Plugins && cap.Plugins.App) {
        // Keep the default (exit) behaviour from firing.
        cap.Plugins.App.addListener('backButton', function () {});
      }
      return docAddEventListener.apply(win.document, args);
    };
  }

  // Ionic WebView compatibility (used by cordova-plugin-ionic and friends).
  var Ionic = (win.Ionic = win.Ionic || {});
  var IonicWebView = (Ionic.WebView = Ionic.WebView || {});
  IonicWebView.getServerBasePath = function (callback) {
    if (cap.Plugins && cap.Plugins.WebView) {
      cap.Plugins.WebView.getServerBasePath().then(function (result) {
        callback(result.path);
      });
    }
  };
  IonicWebView.setServerAssetPath = function (path) {
    cap.Plugins && cap.Plugins.WebView && cap.Plugins.WebView.setServerAssetPath({ path: path });
  };
  IonicWebView.setServerBasePath = function (path) {
    cap.Plugins && cap.Plugins.WebView && cap.Plugins.WebView.setServerBasePath({ path: path });
  };
  IonicWebView.persistServerBasePath = function () {
    cap.Plugins && cap.Plugins.WebView && cap.Plugins.WebView.persistServerBasePath();
  };
  IonicWebView.convertFileSrc = function (url) {
    return cap.convertFileSrc(url);
  };

  cap.withPlugin = function (_pluginId, _fn) {
    return undefined;
  };

  win.Capacitor = cap;
})(typeof window !== 'undefined' ? window : this);
