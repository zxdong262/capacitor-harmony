import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.harmonydemo',
  appName: 'HarmonyDemo',
  webDir: 'www',
  server: {
    url: 'http://localhost/',
    cleartext: true,
  },
  harmony: {
    nodeEntry: 'main.js',
    autostartNode: true,
  },
};

export default config;
