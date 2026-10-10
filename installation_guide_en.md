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

### Prerequisites
* A Mac running **Xcode 15** or later.
* Apple TV 4K running **tvOS 17** or later connected to the same local network as your NAS.

### Step-by-Step
1. Clone the repository to your local machine:
   ```bash
   git clone https://github.com/deedeex/Apple-TV-4K-MediaApp.git
   ```
2. Open the project in Xcode by double-clicking `MediaApp.xcodeproj`.
3. Select your Apple TV (or tvOS Simulator) as the build target.
4. Build and run the project (`⌘ + R`).
5. Open the **Settings** tab in the app to configure your NAS SMB connection details.