import type { CapacitorConfig } from '@capacitor/cli'

const config: CapacitorConfig = {
  // Must match your Apple App ID (reverse-DNS format)
  // Register this at: https://developer.apple.com/account/resources/identifiers/list
  appId: 'com.relevantartist.atlaspassport',
  appName: 'Atlas Passport',

  // For production: point to Vercel deployment
  // For local dev: use 'npx cap run ios' which serves from localhost
  server: {
    url: 'https://atlas-passport.vercel.app',
    cleartext: false, // HTTPS only — never set true for production
  },

  ios: {
    // Minimum iOS version required (App Store requires iOS 16+ as of 2026)
    deploymentTarget: '16.0',
    // Your Apple Team ID — found at developer.apple.com/account
    // Fill in after enrolling in Apple Developer Program ($99/year)
    // teamId: 'XXXXXXXXXX',

    // Background modes — needed for push notifications
    // Add to ios/App/App/Info.plist after running: npx cap add ios
    backgroundColor: '#0a0a0a',

    // Prevents scroll bounce that looks unnatural in a native wrapper
    scrollEnabled: true,
    contentInset: 'always',

    // Hides the status bar background that can clash with dark theme
    allowsLinkPreview: false,
  },

  plugins: {
    // Push Notifications — required native feature to pass App Store review
    // Bare web wrappers get rejected; this adds genuine native value
    PushNotifications: {
      presentationOptions: ['badge', 'sound', 'alert'],
    },

    // Local Notifications — for 72-hour corridor countdown alerts
    LocalNotifications: {
      smallIcon: 'ic_stat_icon_config_sample',
      iconColor: '#C9A84C', // atlas-gold
      sound: 'beep.wav',
    },

    // Haptic feedback for check-in confirmation
    Haptics: {},

    // Share sheet — for the passport share feature
    Share: {},

    // Browser — for any external links (keeps user inside native shell)
    Browser: {
      presentationStyle: 'popover',
    },

    // Status bar styling
    StatusBar: {
      style: 'dark',
      backgroundColor: '#0a0a0a',
    },

    // Splash screen
    SplashScreen: {
      launchShowDuration: 2000,
      launchAutoHide: true,
      backgroundColor: '#0a0a0a',
      androidSplashResourceName: 'splash',
      androidScaleType: 'CENTER_CROP',
      showSpinner: false,
      splashFullScreen: true,
      splashImmersive: true,
    },

    // App — handles foreground/background state
    App: {},
  },
}

export default config
