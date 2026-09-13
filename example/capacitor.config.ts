import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.harmonydemo',
  appName: 'HarmonyDemo',
  webDir: 'www',
  // NOTE: no `server.url` — production loads from the local asset server
  // (http://localhost/ serving rawfile/www).
  harmony: {
    nodeEntry: 'main.js',
    autostartNode: true,
  },
};

export default config;
