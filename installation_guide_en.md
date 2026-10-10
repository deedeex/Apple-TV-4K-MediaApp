# Pingu Player – Media Player for Apple TV (tvOS)

**Pingu Player** is a dedicated Apple TV (tvOS) application designed to seamlessly browse photos and stream videos directly from a local NAS server (e.g., Synology) via SMB.

It operates directly on raw network share files—without relying on iCloud or requiring any file importation into the native Photos library.

---

## 🌟 Key Features & Capabilities

### 🎨 Grid View & Native UI Design
* **Liquid Glass Aesthetics:** Leverages native tvOS glassmorphism and material blur effects (*Liquid Glass*) across key UI components for a modern feel.
* **Media Tile Grid:** Displays photos and videos in a clean, high-density tile grid optimized for browsing large media collections.
* **Full Siri Remote Support:** Native navigation supporting both touch gestures (swiping) and physical click-pad presses.
* **Four Main Tabs:** *All*, *Photos*, *Videos*, and *Settings*.

### 🗂️ Navigation & Sidebar Timeline
* **Dedicated Left Sidebar Timeline:** A structured column on the left side of the screen grouped by years and months.
* **Instant Jump to Period:** Selecting any specific month from the left sidebar instantly scrolls the main grid to that exact timeframe.

### 🎬 Fullscreen Media Viewing & Playback
* **Chronological Flow:** Navigate seamlessly between photos, Live Photos, and video files using the Siri Remote.
* **Live Photo Support:** Play Live Photo animations with a single click of the remote's center button.
* **Instant Video Streaming (including 4K HDR):** Videos start playing in approximately one second because content is streamed directly from the NAS rather than downloaded completely.
* **Post-Playback Controls:** Clear action buttons (*"Previous"*, *"Replay"*, and *"Next"*) appear as soon as a video ends.

### ⚡ Performance & Dual-Tier Caching (100k+ Files)
* **Instant Launch:** Shows cached file indexes immediately upon startup, running background library updates seamlessly.
* **Dual-Tier Caching (RAM + Local Storage):** Utilizes two levels of cache for both thumbnails and media assets (fast RAM + Apple TV local storage). This eliminates redundant network requests to the NAS and guarantees smooth scrolling and playback even with 100,000+ files.
* **Smart Pre-loading:** Pre-renders adjacent media items in the background for ultra-fast fullscreen transitions.

### ⚙️ Preferences & Management
* **Server Status & Library Maintenance:** View current server connection details, trigger a manual library refresh, or clear cached data on demand.
* **Configurable Connection:** Fully edit SMB credentials and network settings: host IP/name, share name, user credentials, and photo directory path.
* **Personalization:** Select app language (English and Polish) and customize the application background.

---

## 🚀 Installation & Setup Guide

Since this application is not distributed via the App Store, building and installing it requires using **Xcode** and your own (free) Apple ID account.

The installation process takes about 5 minutes and involves a few simple configuration steps.

### Prerequisites
* A **Mac** computer with **Xcode** installed (available for free in the Mac App Store).
* An **Apple TV** connected to the same Wi-Fi / LAN network as your Mac.
* A free **Apple ID account** logged into Xcode.

### Step 1: Download the Source Code

Clone the repository to your Mac using Terminal:
```bash
git clone https://github.com/deedeex/Apple-TV-4K-MediaApp.git
```
OR download the ZIP archive directly from GitHub and extract it on your drive.

### Step 2: Open the Project in Xcode

1. Open the folder containing the downloaded project.
2. Double-click **`MediaApp.xcodeproj`** (or `MediaApp.xcworkspace` if present) to launch Xcode.

### Step 3: Add Your Apple ID Account in Xcode

If you haven't added your Apple ID to Xcode yet:
1. In the top menu bar, go to: **Xcode** → **Settings...** (or press `⌘ + ,`).
2. Navigate to the **Accounts** tab.
3. Click the **`+`** button in the bottom-left corner and select **Apple ID**.
4. Log in using your Apple ID credentials.

### Step 4: Configure Code Signing (Signing & Capabilities)

To install the application on a physical Apple TV, you need to assign a signing profile:
1. In the left Navigator panel, click the top project node – **`MediaApp`**.
2. In the main editor view, select the target named **`MediaApp`**.
3. Go to the **Signing & Capabilities** tab.
4. Enable **Automatically manage signing**.
5. Under **Team**, select your account from the dropdown list (it will display your name as *Personal Team*).
6. In the **Bundle Identifier** field, update the identifier to something unique (e.g., append your initials: `com.tworaj.MediaApp.myversion`) to avoid naming collisions on Apple servers.

### Step 5: Pair Apple TV with Xcode

If your Apple TV isn't paired with Xcode yet:
1. Make sure **both Apple TV and Mac are on the same local network**.
2. On your Apple TV, go to **Settings** → **Remotes and Devices** → **Remote App and Devices**.
3. In Xcode on your Mac, select from the top menu: **Window** → **Devices and Simulators** (or press `⇧ + ⌘ + 2`).
4. Under the **Devices** tab on the left, select your Apple TV and click **Pair**.
5. Enter the PIN code shown on your TV screen into the prompt in Xcode.

### Step 6: Enable Developer Mode on Apple TV (tvOS 16+)

1. On your Apple TV, go to **Settings** → **Privacy & Security**.
2. Scroll down to **Developer Mode** and turn it **On**.
3. Confirm the reboot request.
4. After restarting, confirm enabling Developer Mode on your TV screen and enter your passcode if prompted.

### Step 7: Select Target Device and Run

1. In the top bar of Xcode (next to the ▶ Play button), click the target device dropdown.
2. Choose your physical **Apple TV** (or *tvOS Simulator* if testing on Mac).
3. Click **Run** (the ▶ button) or press **`⌘ + R`**.
4. Xcode will compile, install, and automatically launch the app on your Apple TV.

### Step 8: First Connection Setup

1. Open the **Settings** tab in the app on your Apple TV.
2. Enter your NAS credentials:
   * **Host / IP:** Local IP address of your NAS (e.g., `192.168.1.100`).
   * **Share:** Shared folder name (e.g., `photo` or `home`).
   * **Path:** Path to your photo/video directory (optional).
   * **Username & Password:** Your NAS user credentials with read access.
3. Save settings – the app will begin indexing and caching your media library!