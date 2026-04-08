#Requires AutoHotkey v2.0
#UseHook

; Prevents the Start Menu from appearing when using Windows key modifiers
A_MenuMaskKey := "vkE8"

; ==============================================================================
; CONFIGURATION SECTION: Modify these variables to match your setup
; ==============================================================================

; 1. BROWSER PATH: Path to the browser executable handling the PWA
targetPath := '"C:\Program Files\BraveSoftware\Brave-Browser\Application\chrome_proxy.exe"'

; 2. APP ARGUMENTS: Profile directory and Gemini App ID
args := '--profile-directory="Profile 4" --app-id=gdfaincndogidkdcdkhapmbffkckdkhn'

; 3. WINDOW TITLE: Used to identify the Gemini window
winTitle := "Gemini ahk_exe brave.exe"

; 4. EXCLUDE TITLE: Ignore standard Brave browser tabs to prevent misfires
excludeTitle := "- Brave"

; 5. TASKBAR POSITION: Where Gemini is pinned (e.g., "#4" for the 4th icon)
taskbarPosition := "#4"

; ==============================================================================
; CORE LOGIC: Do not modify below unless necessary
; ==============================================================================

; Ensure the script runs with Administrator privileges to avoid UAC blocks
if !A_IsAdmin {
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
    } catch {
        MsgBox("Administrator permissions are required for full functionality.", "Error", 16)
    }
    ExitApp()
}

; Set matching behavior: 1 = Window title must start with the specified string
SetTitleMatchMode(1) 
fullCommand := targetPath . " " . args

; ------------------------------------------------------------------------------
; HOTKEY 1: Single Press Copilot Button (Toggle Logic)
; Captures Win+C or Win+Shift+F23 (Default Copilot key behavior)
; ------------------------------------------------------------------------------
$#c::
$<+#f23::
{
    ; Wait for the user to physically release the keys to prevent signal overlap
    KeyWait("LWin")
    KeyWait("RWin")
    KeyWait("Shift")
    
    ; Send a dummy keystroke to cancel the Start Menu trigger
    Send("{Blind}{vkE8}")
    
    ; Brief pause to let the Windows input queue stabilize
    Sleep(50)

    if WinExist(winTitle, , excludeTitle) {
        ; Use SendEvent for more reliable interaction with the Windows Taskbar
        SendEvent(taskbarPosition)
    } else {
        ; Launch the PWA if it is not currently open
        Run(fullCommand)
    }
}

; ------------------------------------------------------------------------------
; HOTKEY 2: Ctrl + Copilot Button (Force a new window instance)
; ------------------------------------------------------------------------------
$^#c::
$^<+#f23::
{
    ; Wait for physical key release including Ctrl
    KeyWait("LWin")
    KeyWait("RWin")
    KeyWait("Shift")
    KeyWait("Ctrl")
    
    ; Mask the Start Menu
    Send("{Blind}{vkE8}")
    Sleep(50)
    
    ; Directly launch a fresh instance
    Run(fullCommand)
}
