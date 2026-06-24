# Atlas Passport — Apple App Store Submission Checklist
## $99/year · 2–5 day review · Capacitor iOS wrapper

---

## PHASE 1 — Before You Start (Prerequisites)

- [ ] **Enroll in Apple Developer Program** — https://developer.apple.com/programs/enroll/
  - $99/year, credit card required, takes 24–48 hours to activate
  - Register as **Individual** (or **Organization** if you have a D-U-N-S number)
- [ ] **Mac with Xcode 16+ installed** — required to build/sign the iOS app
  - Download free from Mac App Store
  - Requires macOS 14.5+
- [ ] **Apple ID** enrolled in the Developer Program

---

## PHASE 2 — App Setup

### 2a. Register an App ID
- [ ] Go to https://developer.apple.com/account/resources/identifiers/list
- [ ] Click (+) → App IDs → App
- [ ] Bundle ID: `com.relevantartist.atlaspassport` (reverse DNS, must match `capacitor.config.ts`)
- [ ] Enable capabilities: **Push Notifications**, **Associated Domains**

### 2b. Create App in App Store Connect
- [ ] Go to https://appstoreconnect.apple.com
- [ ] My Apps → (+) → New App
- [ ] Platform: iOS
- [ ] Name: **Atlas Passport**
- [ ] Bundle ID: `com.relevantartist.atlaspassport`
- [ ] SKU: `atlas-passport-001` (internal reference, not shown to users)
- [ ] User Access: Full Access

---

## PHASE 3 — Install Capacitor & Build iOS

Run from the Atlas Passport repo root:

```bash
# 1. Install Capacitor packages (see package.additions.json)
npm install --legacy-peer-deps @capacitor/core @capacitor/app @capacitor/browser \
  @capacitor/haptics @capacitor/local-notifications @capacitor/push-notifications \
  @capacitor/share @capacitor/splash-screen @capacitor/status-bar
npm install --legacy-peer-deps -D @capacitor/cli @capacitor/ios

# 2. Initialize Capacitor (first time only)
npx cap init "Atlas Passport" com.relevantartist.atlaspassport --web-dir=.next

# 3. Add iOS platform
npx cap add ios

# 4. Sync web assets to native project
npx cap sync ios

# 5. Open in Xcode
npx cap open ios
```

### 3a. In Xcode
- [ ] Set **Team** to your Apple Developer account (Signing & Capabilities tab)
- [ ] Confirm **Bundle Identifier** = `com.relevantartist.atlaspassport`
- [ ] Set **Deployment Target** = iOS 16.0
- [ ] Add Push Notifications capability
- [ ] Add Background Modes: Remote notifications
- [ ] Build to confirm no errors (Cmd+B)

---

## PHASE 4 — Required Assets

### Icons (generate all from a single 1024×1024 source PNG)
Use https://www.appicon.co or Xcode's asset generator

| Size | Usage |
|---|---|
| 1024×1024 | App Store listing |
| 180×180 | iPhone home screen (@3x) |
| 120×120 | iPhone home screen (@2x) |
| 167×167 | iPad Pro |
| 152×152 | iPad Retina |

### Screenshots (required: iPhone 6.9" = 1320×2868 px)
- [ ] Home/activation screen
- [ ] Active passport with corridor progress
- [ ] Check-in confirmation screen
- [ ] Reward unlock screen
- Minimum 1 screenshot required; 3–5 recommended
- Capture in iOS Simulator (Xcode → Simulator → File → Take Screenshot)

### App Preview Video (optional but recommended)
- 15–30 seconds, same resolution as screenshots
- Shows the check-in and corridor flow

---

## PHASE 5 — App Store Connect Metadata

### App Information
- [ ] **Name:** Atlas Passport
- [ ] **Subtitle:** 72 Hours. One Corridor. (30 char max)
- [ ] **Primary Category:** Travel
- [ ] **Secondary Category:** Lifestyle

### Description
```
Atlas Passport is a 72-hour real-world activation game set across curated 
urban corridors in Washington DC.

Activate your passport. Visit each node within your corridor — 
restaurants, rooftops, cultural venues, and landmark stays. 
Complete the corridor within 72 hours to unlock your reward.

Three corridors. Fourteen nodes. One window to move.

— Founders Corridor (The Wharf, DC)
— Georgetown Passage
— National Harbor Corridor

Presented by Relevant Artist.
```

### Keywords (100 chars max, comma-separated)
```
travel,DC,passport,game,corridor,urban,activation,explore,Relevant Artist,Atlas
```

### Privacy Policy URL
- [ ] Publish a privacy policy at `atlas-passport.vercel.app/privacy`
- [ ] Must cover: data collected, Supabase usage, Resend email, no sale of data

### Age Rating
- [ ] Complete questionnaire in App Store Connect
- Recommended result: **4+** (no objectionable content)

---

## PHASE 6 — Privacy & Compliance (NEW 2025–2026 Requirements)

### App Privacy "Nutrition Labels"
Complete the Data collection section in App Store Connect:

| Data Type | Collected? | Linked to User? | Used for Tracking? |
|---|---|---|---|
| Email address | Yes | Yes | No |
| Name | Yes | Yes | No |
| User ID | Yes | Yes | No |
| Crash data | Yes (Vercel) | No | No |
| Usage data | Yes (Vercel Analytics) | No | No |
| Location | No | — | — |

### Privacy Manifest (PrivacyInfo.xcprivacy)
Required file in your Xcode project. Add to `ios/App/App/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <!-- Add if you use UserDefaults -->
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>CA92.1</string></array>
    </dict>
  </array>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyTracking</key>
  <false/>
</dict>
</plist>
```

### AI Consent Disclosure
- [ ] If Resend or any AI service routes user email data externally, disclose in metadata
- [ ] Add to App Privacy section: "Email address used to send transactional notifications"

### Account Deletion
- [ ] Add a "Delete Account" option in the app settings
- [ ] Required if users can create accounts — mandatory since 2023, enforced strictly

---

## PHASE 7 — Submit for Review

### Before submitting:
- [ ] All screenshots uploaded
- [ ] Privacy policy URL working
- [ ] Metadata complete
- [ ] App Privacy labels filled
- [ ] Demo account provided in "Review Notes":
  ```
  Test account:
  Email: reviewer@atlaspassport.com
  Password: AtlasReview2026!
  Note: Demo account has a pre-activated passport in the Founders Corridor.
  ```
- [ ] No placeholder content in the app
- [ ] All links/buttons functional
- [ ] App does not crash on launch

### Submit:
1. Archive build in Xcode (Product → Archive)
2. Upload to App Store Connect via Organizer
3. In App Store Connect: select the build, complete all sections, click "Submit for Review"

---

## TIMELINE

| Phase | Estimated Time |
|---|---|
| Enrollment approval | 1–2 days |
| Capacitor setup + Xcode config | 1 day |
| Asset creation (icons, screenshots) | 1 day |
| Metadata + compliance forms | 2–3 hours |
| Apple Review | 2–5 business days |
| **Total to live** | **~1–2 weeks** |

---

## COST SUMMARY

| Item | Cost |
|---|---|
| Apple Developer Program | $99/year |
| Mac (required for Xcode) | Must own one |
| All other tooling | Free |
| **Total year 1** | **$99** |

---

## REJECTION RISKS FOR ATLAS PASSPORT

| Risk | Mitigation |
|---|---|
| Bare web wrapper (Guideline 4.2) | ✅ Mitigated — Capacitor adds push notifications, haptics, local notifications, share sheet |
| Missing account deletion | Add "Delete Account" to profile settings before submitting |
| Missing privacy policy | Publish at `/privacy` before submitting |
| Demo account not provided | Create a dedicated reviewer account with pre-activated passport |
| Old SDK | ✅ Mitigated — `@capacitor/ios` v7 targets iOS 16+ with current SDK |
