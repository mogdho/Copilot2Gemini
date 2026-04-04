#Requires AutoHotkey v2.0

; =====================================================================
; ⚙️ USER CONFIGURATION SECTION - PLEASE UPDATE THESE VARIABLES
; =====================================================================

; 1. BROWSER PATH: Replace with your browser's proxy or executable path.
; Example: '"C:\Program Files\Google\Chrome\Application\chrome_proxy.exe"'
targetPath := '"YOUR_BROWSER_PATH_HERE"'

; 2. APP ARGUMENTS: Replace Profile Name and App ID.
; Example: '--profile-directory="Default" --app-id=gdfaincndogidkdcdkhapmbffkckdkhn'
args := '--profile-directory="YOUR_PROFILE_HERE" --app-id=YOUR_APP_ID_HERE'

; 3. WINDOW EXECUTABLE: Change 'brave.exe' to 'chrome.exe' or 'msedge.exe' if needed.
; Example: "Gemini ahk_exe chrome.exe"
winTitle := "Gemini ahk_exe YOUR_BROWSER_EXE_HERE"

; 4. EXCLUDE TITLE: Prevents matching regular browser windows.
; Example: "- Google Chrome" or "- Brave"
excludeTitle := "- YOUR_BROWSER_NAME_HERE"

; 5. TASKBAR POSITION: Change the number '4' to wherever your PWA is pinned.
; Example: If it's the 2nd icon on your taskbar, change "#4" to "#2".
taskbarPosition := "#4"

; =====================================================================
; 🛑 END OF CONFIGURATION - DO NOT MODIFY BELOW UNLESS YOU KNOW AHK
; =====================================================================

if !A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

SetTitleMatchMode(1) 

fullCommand := targetPath . " " . args

<+#f23::
#c::
{
    if WinExist(winTitle, , excludeTitle) {
        Send(taskbarPosition) 
    } else {
        Run(fullCommand)
    }
}


^<+#f23::
^#c::
{
    Run(fullCommand)
}
