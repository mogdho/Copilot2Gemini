#Requires AutoHotkey v2.0
#UseHook ; Forces the use of the keyboard hook to override default Windows shortcuts

; ==============================================================================
; 🔵 CONFIGURATION SECTION: Modify these values according to your setup
; ==============================================================================

; 1. BROWSER PATH: Provide the exact path to your browser's executable (e.g., chrome_proxy.exe for Brave/Chrome PWAs)
targetPath := '"C:\Program Files\BraveSoftware\Brave-Browser\Application\chrome_proxy.exe"'

; 2. APP ARGUMENTS: Add your profile directory and the specific App ID for the Gemini PWA
; You can find the App ID in the properties of your PWA desktop shortcut.
args := '--profile-directory="Profile 4" --app-id=gdfaincndogidkdcdkhapmbffkckdkhn'

; 3. WINDOW TITLE: The exact title or ahk_exe used to identify the PWA window
; Example: "Gemini ahk_exe brave.exe" or "Gemini ahk_exe chrome.exe"
winTitle := "Gemini ahk_exe brave.exe"

; 4. EXCLUDE TITLE: Prevents the script from triggering on regular browser tabs
excludeTitle := "- Brave"

; 5. TASKBAR POSITION: The position of your pinned Gemini PWA on the taskbar.
; For example, if it's the 4th icon, use "#4". This uses the native Win + Number toggle logic.
taskbarPosition := "#4"

; ==============================================================================
; 🛑 END OF CONFIGURATION - Do not modify below unless you know what you are doing
; ==============================================================================

; Request Administrator privileges automatically (Required to prevent conflicts with elevated windows)
if !A_IsAdmin {
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
    } catch {
        MsgBox "Admin permissions are required for full functionality. The script will now exit.", "Permission Error", 16
    }
    ExitApp()
}

; Set matching behavior: 1 = Window title must start with the specified string
SetTitleMatchMode(1) 
fullCommand := targetPath . " " . args

; ------------------------------------------------------------------------------
; HOTKEY 1: Single Press Copilot Button (Toggle Logic: Open/Minimize/Restore)
; The '$' prefix prevents the default Windows Search/Copilot overlay from appearing
; ------------------------------------------------------------------------------
$#c::
$<+#f23::
{
    if WinExist(winTitle, , excludeTitle) {
        ; If the window exists, use the native Windows taskbar shortcut to toggle focus/minimize
        Send(taskbarPosition)
    } else {
        ; If the window does not exist, launch the PWA
        Run(fullCommand)
    }
}

; ------------------------------------------------------------------------------
; HOTKEY 2: Ctrl + Copilot Button (Always open a fresh new window)
; ------------------------------------------------------------------------------
$^#c::
$^<+#f23::
{
    Run(fullCommand)
}
