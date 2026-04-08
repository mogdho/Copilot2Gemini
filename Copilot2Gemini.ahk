#Requires AutoHotkey v2.0
#UseHook ; Forces the use of the keyboard hook to override default Windows shortcuts

; Start Menu pop-up fix - A_MenuMaskKey update
A_MenuMaskKey := "vkE8"

; ==============================================================================
; 🔵 CONFIGURATION SECTION: Modify these values according to your setup
; ==============================================================================

; 1. BROWSER PATH: Provide the exact path to your browser's executable
targetPath := '"C:\Program Files\BraveSoftware\Brave-Browser\Application\chrome_proxy.exe"'

; 2. APP ARGUMENTS: Add your profile directory and the specific App ID for the Gemini PWA
args := '--profile-directory="Profile 4" --app-id=gdfaincndogidkdcdkhapmbffkckdkhn'

; 3. WINDOW TITLE: The exact title or ahk_exe used to identify the PWA window
winTitle := "Gemini ahk_exe brave.exe"

; 4. EXCLUDE TITLE: Prevents the script from triggering on regular browser tabs
excludeTitle := "- Brave"

; 5. TASKBAR POSITION: The position of your pinned Gemini PWA on the taskbar.
taskbarPosition := "#4"

; ==============================================================================
; 🛑 END OF CONFIGURATION - Do not modify below unless you know what you are doing
; ==============================================================================

; Request Administrator privileges automatically
if !A_IsAdmin {
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
    } catch {
        MsgBox "Admin permissions are required for full functionality. The script will now exit.", "Permission Error", 16
    }
    ExitApp()
}

SetTitleMatchMode(1) 
fullCommand := targetPath . " " . args

; ------------------------------------------------------------------------------
; HOTKEY 1: Single Press Copilot Button (Toggle Logic: Open/Minimize/Restore)
; ------------------------------------------------------------------------------
$#c::
$<+#f23::
{
    ; Start Menu pop-up block command
    Send "{Blind}{vkE8}"
    
    if WinExist(winTitle, , excludeTitle) {
        Send(taskbarPosition)
    } else {
        Run(fullCommand)
    }
}

; ------------------------------------------------------------------------------
; HOTKEY 2: Ctrl + Copilot Button (Always open a fresh new window)
; ------------------------------------------------------------------------------
$^#c::
$^<+#f23::
{
    ; Start Menu pop-up block command
    Send "{Blind}{vkE8}"
    
    Run(fullCommand)
}
