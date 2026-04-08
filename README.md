# 🚀 Copilot2Gemini
![AutoHotkey](https://img.shields.io/badge/Language-AutoHotkey_v2.0-red?style=for-the-badge&logo=autohotkey)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Windows-blue?style=for-the-badge&logo=windows)

**Copilot2Gemini** is an advanced AutoHotkey v2 script that remaps the physical Windows Copilot key (or `Win + C`) to launch the Google Gemini Progressive Web App (PWA). It utilizes a clever taskbar-pinning logic to flawlessly handle minimizing and restoring the PWA window, avoiding the common focus issues associated with web apps.

### ✨ Key Features
* **Smart Toggle:** Replaces Copilot with Gemini PWA. Pressing the button will open the app, minimize it if it's currently focused, or restore it if it's minimized.
* **Force New Instance:** Use `Ctrl + Copilot` to bypass the toggle logic and force a fresh, new window of Gemini.
* **Auto-Admin Elevation:** Self-elevates to Administrator to ensure shortcut interception works system-wide.
* **Universal Browser Support:** Works with Chrome, Brave, or Edge (requires minor configuration).
* **Ghost Start Menu Fix:** Utilizes physical key release detection (KeyWait) and system masking (vkE8) to guarantee the Windows Start Menu never accidentally triggers after pressing the Copilot button.

---

### ⚙️ Step-by-Step Setup Guide

Since system configurations and browser profiles vary, you must install the PWA and configure the script manually before running it.

#### Step 1: Install the Gemini PWA
1. Open your Chromium-based browser (Chrome, Brave, Edge) and go to [gemini.google.com](https://gemini.google.com).
2. Click the browser's **3-dot menu** (top right).
3. Go to **Save and share** (or Apps) > **Install page as app...**
4. Name it "Gemini" and click **Install**.

#### Step 2: Find Your Target Path & App ID
1. Open your browser and type `chrome://apps` (or `brave://apps`) in the address bar.
2. Right-click on the newly installed **Gemini** app and select **Create shortcuts** (check only the Desktop option).
3. Go to your Windows Desktop, right-click the **Gemini** shortcut, and select **Properties**.
4. Look at the **Target** field. It will look something like this:
`"C:\Program Files\Google\Chrome\Application\chrome_proxy.exe" --profile-directory="Default" --app-id=gdfaincndogidkdcdkhapmbffkckdkhn`

#### Step 3: Configure the Script
Open `Copilot2Gemini.ahk` in a text editor. You need to update two lines of code using the information from Step 2.

**Target Path:**
Replace the path with your browser's executable path (keep the single and double quotes exactly as shown).

```autohotkey
targetPath := '"C:\Program Files\Google\Chrome\Application\chrome_proxy.exe"'
```
Arguments (Profile & App ID):
Paste your specific profile directory and app-id here.

```autohotkey
args := '--profile-directory="Default" --app-id=YOUR_APP_ID_HERE'
```
#### Step 4: Pin to Taskbar
Pin the Gemini PWA to your Windows Taskbar. Count its position from left to right (excluding the Start Button and Widgets).

By default, the script assumes it is the 4th pinned app (Send("#4")).

If you pin it in a different position (e.g., 2nd), open the script in a text editor and update the taskbarPosition variable in the Configuration Section (e.g., taskbarPosition := "#2").

### 🚀 Installation & Usage
1. Verify that [AutoHotkey v2.0+](https://www.autohotkey.com/) is installed on your operating system.
2. Download the script file from this repository.
3. Execute the file to initialize the background process.

> **Note:** To automate execution upon system boot, press `Win + R`, type `shell:startup` and paste the script file there. Ensure it has Administrator privileges to function correctly.

Pro Tip: For a silent, automatic background startup, schedule the script via Windows Task Scheduler and ensure you check the "Run with highest privileges" option.
---
### 🔗 Download/Source link
- Download/Source link - https://github.com/mogdho/Copilot2Gemini
