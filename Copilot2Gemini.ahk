#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName Copilot2Gemini
;@Ahk2Exe-SetDescription Copilot2Gemini
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-SetCompanyName Mogdho Paul
;@Ahk2Exe-SetCopyright Mogdho Paul - MIT License
;@Ahk2Exe-SetMainIcon assets\icon.ico
;  (Lines starting with ;@Ahk2Exe are only read when building the .exe)


#SingleInstance Force
#UseHook

; Prevents the Start Menu from appearing when using Windows key modifiers
A_MenuMaskKey := "vkE8"

; ==============================================================================
; No manual setup needed: the script finds web apps installed from Chrome,
; Brave or Edge by itself (Gemini, ChatGPT, Claude, ...). Pick one from the
; tray menu → "Assistant". Your choice is saved in Copilot2Gemini.ini.
; ==============================================================================

; Opened in your normal browser if no assistant app is installed yet
FallbackUrl := "https://gemini.google.com"

AppName      := "Copilot2Gemini"
SettingsFile := A_ScriptDir "\Copilot2Gemini.ini"
IsPaused     := false
Apps         := []     ; Installed web apps found on this PC
Current      := ""     ; The chosen assistant (one entry of Apps)

; Run as admin so the hotkeys also work while an elevated window is focused
if !A_IsAdmin {
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
    } catch {
        MsgBox("Administrator permissions are required for full functionality.", "Error", 16)
    }
    ExitApp()
}

LoadApps(true)
SetupTray()

; ------------------------------------------------------------------------------
; HOTKEY 1: Copilot key / Win+C (Copilot key sends Win+Shift+F23)
; In front → minimize, open but behind → bring to front, not open → launch
; ------------------------------------------------------------------------------
$#c::
$<+#f23::ToggleAssistant()

; ------------------------------------------------------------------------------
; HOTKEY 2: Ctrl + Copilot key → always open an extra window
; ------------------------------------------------------------------------------
$^#c::
$^<+#f23::LaunchAssistant()

ToggleAssistant() {
    if !IsObject(Current) {
        LaunchAssistant()
        return
    }
    hwnd := FindAppWindow(Current)
    if !hwnd {
        LaunchAssistant()
        return
    }
    ; A minimized window can still count as "active", so check that too —
    ; otherwise the key would just minimize it again instead of showing it.
    if WinActive(hwnd) && WinGetMinMax(hwnd) != -1
        WinMinimize(hwnd)
    else
        ShowAppWindow(hwnd)
}

; Restore and focus the window. If Windows refuses the focus change
; (it sometimes does while keys are held), try a second way.
ShowAppWindow(hwnd) {
    if WinGetMinMax(hwnd) = -1
        WinRestore(hwnd)
    WinActivate(hwnd)
    if !WinWaitActive(hwnd, , 0.5)
        DllCall("SwitchToThisWindow", "ptr", hwnd, "int", true)
}

; Launch WITHOUT admin rights. A plain Run() from this elevated script would
; start the whole browser as administrator if it isn't already open.
LaunchAssistant() {
    target := IsObject(Current) ? Current.target : FallbackUrl
    args   := IsObject(Current) ? Current.args : ""
    try {
        ShellRun(target, args)
    } catch {
        Run(IsObject(Current) ? '"' target '" ' args : target)
    }
}

; ==============================================================================
; FINDING INSTALLED WEB APPS
; ==============================================================================

; Scan shortcuts for browser web apps (they launch "chrome_proxy.exe --app-id=...")
FindInstalledApps() {
    found := Map()
    shortcuts := []
    for dir in [A_StartMenu "\Programs", A_StartMenuCommon "\Programs", A_Desktop, A_DesktopCommon]
        loop files dir "\*.lnk", "R"
            shortcuts.Push(A_LoopFileFullPath)
    ; Every browser profile also keeps a copy of each app's shortcut
    appData := EnvGet("LOCALAPPDATA")
    for userData in [appData "\Google\Chrome\User Data", appData "\BraveSoftware\Brave-Browser\User Data", appData "\Microsoft\Edge\User Data"]
        loop files userData "\*", "D"
            loop files A_LoopFileFullPath "\Web Applications\_crx_*", "D"
                loop files A_LoopFileFullPath "\*.lnk"
                    shortcuts.Push(A_LoopFileFullPath)

    for lnk in shortcuts {
        try FileGetShortcut(lnk, &target, , &args)
        catch
            continue
        if !RegExMatch(args, "--app-id=(\w+)", &id) || !FileExist(target)
            continue
        profile := RegExMatch(args, '--profile-directory=(?:"([^"]+)"|(\S+))', &p) ? p[1] p[2] : "Default"
        key := id[1] "|" profile
        if !found.Has(key) {
            SplitPath(lnk, , , , &name)
            found[key] := {key: key, name: name, id: id[1], profile: profile, target: target, args: Trim(args)}
        }
    }

    ; Sort by name; show the profile when the same app exists in several profiles
    list := []
    for , app in found
        list.Push(app)
    loop list.Length - 1 {
        i := A_Index
        loop list.Length - i
            if StrCompare(list[A_Index].name, list[A_Index + 1].name) > 0 {
                tmp := list[A_Index], list[A_Index] := list[A_Index + 1], list[A_Index + 1] := tmp
            }
    }
    for app in list {
        app.label := app.name
        for other in list
            if ObjPtr(other) != ObjPtr(app) && other.name = app.name
                app.label := app.name " (" app.profile ")"
    }
    return list
}

; Find (re)load apps and pick the saved one — or Gemini on first run
LoadApps(firstStart := false) {
    global Apps, Current
    Apps := FindInstalledApps()
    Current := ""
    saved := IniRead(SettingsFile, "Assistant", "App", "")
    for app in Apps
        if app.key = saved
            Current := app
    if !IsObject(Current) {
        for app in Apps
            if InStr(app.name, "Gemini") {
                Current := app
                break
            }
        if IsObject(Current) {
            IniWrite(Current.key, SettingsFile, "Assistant", "App")
            if firstStart
                TrayTip("Found " Current.name ". Press the Copilot key to open it.`nRight-click the tray icon to pick a different assistant.", AppName)
        } else if firstStart {
            TrayTip("No Gemini app found, so the Copilot key opens " FallbackUrl " in your browser.`nRight-click the tray icon for help.", AppName)
        }
    }
}

; Chromium tags each app window with an ID like "Brave._crx_<app id>" (long IDs get
; shortened in the middle), so match on the start and end of the app id.
FindAppWindow(app) {
    for hwnd in WinGetList("ahk_class Chrome_WidgetWin_1") {
        if WinGetTitle(hwnd) = ""
            continue
        aumid := GetWindowAppId(hwnd)
        if InStr(aumid, "_crx_" SubStr(app.id, 1, 10)) && InStr(aumid, SubStr(app.id, -12))
            return hwnd
    }
    return 0
}

GetWindowAppId(hwnd) {
    static IID_IPropertyStore := GuidBuffer("{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}")
    static PKEY_AppUserModel_ID := PropKey("{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}", 5)
    if DllCall("shell32\SHGetPropertyStoreForWindow", "ptr", hwnd, "ptr", IID_IPropertyStore, "ptr*", &store := 0) != 0
        return ""
    value := Buffer(24, 0), result := ""
    try {
        ComCall(5, store, "ptr", PKEY_AppUserModel_ID, "ptr", value)    ; IPropertyStore::GetValue
        if NumGet(value, 0, "ushort") = 31                              ; VT_LPWSTR
            result := StrGet(NumGet(value, 8, "ptr"), "UTF-16")
        DllCall("ole32\PropVariantClear", "ptr", value)
    }
    ObjRelease(store)
    return result
}

GuidBuffer(str) {
    buf := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", str, "ptr", buf)
    return buf
}

PropKey(guid, pid) {
    buf := Buffer(20)
    DllCall("ole32\CLSIDFromString", "wstr", guid, "ptr", buf)
    NumPut("uint", pid, buf, 16)
    return buf
}

; Runs a program through Explorer, so it starts at normal (non-admin) level.
; Based on the ShellRun example in the AutoHotkey v2 documentation.
ShellRun(prms*) {
    shellWindows := ComObject("Shell.Application").Windows
    desktop := shellWindows.FindWindowSW(0, 0, 8, 0, 1)  ; SWC_DESKTOP, SWFO_NEEDDISPATCH
    tlbs := ComObjQuery(desktop,
        "{4C96BE40-915C-11CF-99D3-00AA004AE837}",  ; SID_STopLevelBrowser
        "{000214E2-0000-0000-C000-000000000046}")  ; IID_IShellBrowser
    ComCall(15, tlbs, "ptr*", sv := ComValue(13, 0))  ; IShellBrowser.QueryActiveShellView
    NumPut("int64", 0x20400, "int64", 0x46000000000000C0, IID_IDispatch := Buffer(16))
    ComCall(15, sv, "uint", 0, "ptr", IID_IDispatch, "ptr*", sfvd := ComValue(9, 0))  ; IShellView.GetItemObject
    sfvd.Application.ShellExecute(prms*)
}

; ==============================================================================
; ASSISTANT MENU
; ==============================================================================
BuildAssistantMenu() {
    m := Menu()
    for app in Apps {
        m.Add(app.label, PickAssistant.Bind(app))
        if IsObject(Current) && app.key = Current.key
            m.Check(app.label)
    }
    if Apps.Length = 0 {
        m.Add("(no web apps found)", (*) => 0)
        m.Disable("(no web apps found)")
    }
    m.Add()
    m.Add("Rescan installed apps", RescanApps)
    m.Add("How to add an assistant…", ShowAddHelp)
    return m
}

PickAssistant(app, *) {
    global Current := app
    IniWrite(app.key, SettingsFile, "Assistant", "App")
    SetupTray()
}

RescanApps(*) {
    LoadApps()
    SetupTray()
    TrayTip("Found " Apps.Length " web app(s).", AppName)
}

ShowAddHelp(*) {
    MsgBox("To use ChatGPT, Claude or any other site with the Copilot key:`n`n"
        . "1. Open the site in Chrome, Brave or Edge.`n"
        . "2. Click the ⋮ menu → Save and share (or Apps) → Install page as app…`n"
        . "3. Right-click this tray icon → Assistant → Rescan installed apps.`n"
        . "4. Pick it from the Assistant list.", AppName, "Iconi")
}

; ==============================================================================
; PAUSE
; ==============================================================================
TogglePause(*) {
    global IsPaused := !IsPaused
    Suspend(IsPaused)                 ; Copilot key goes back to its normal Windows behaviour
    UpdateTray()
}

; ==============================================================================
; TRAY MENU + START WITH WINDOWS  (same block in all three scripts)
; ==============================================================================
SetupTray() {
    tray := A_TrayMenu
    tray.Delete()
    tray.Add(AppName, (*) => 0)
    tray.Disable(AppName)
    tray.Add()
    tray.Add("Assistant", BuildAssistantMenu())
    tray.Add("Pause", TogglePause)
    tray.Add("Start with Windows", ToggleStartup)
    tray.Add()
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Pause"           ; Double-click the tray icon = pause / resume
    OnMessage(0x1A, OnThemeChange)    ; WM_SETTINGCHANGE: follow light/dark taskbar
    UpdateTray()
}

UpdateTray() {
    RefreshIcon()
    A_IconTip := AppName " → " (IsObject(Current) ? Current.label : "browser") (IsPaused ? " (paused)" : "")
    if IsPaused
        A_TrayMenu.Check("Pause")
    else
        A_TrayMenu.Uncheck("Pause")
    if StartupEnabled()
        A_TrayMenu.Check("Start with Windows")
    else
        A_TrayMenu.Uncheck("Start with Windows")
}

StartupTaskName() => AppName " (AutoHotkey)"

; True if a logon task exists AND points at this script's current location
StartupEnabled() {
    try {
        svc := ComObject("Schedule.Service")
        svc.Connect()
        task := svc.GetFolder("\").GetTask(StartupTaskName())
        return InStr(task.Definition.Actions.Item(1).Arguments, A_ScriptFullPath)
            || task.Definition.Actions.Item(1).Path = A_ScriptFullPath
    }
    return false
}

ToggleStartup(*) {
    try {
        svc := ComObject("Schedule.Service")
        svc.Connect()
        root := svc.GetFolder("\")
        if StartupEnabled() {
            root.DeleteTask(StartupTaskName(), 0)
        } else {
            ; Task Scheduler starts the script with admin rights at logon — no UAC pop-up
            user := EnvGet("USERDOMAIN") "\" A_UserName
            td := svc.NewTask(0)
            td.RegistrationInfo.Description := "Starts " AppName " when you log in."
            td.Principal.RunLevel := 1                   ; Run with highest privileges
            td.Principal.LogonType := 3                  ; Only when the user is logged on
            td.Settings.DisallowStartIfOnBatteries := false
            td.Settings.StopIfGoingOnBatteries := false
            td.Settings.ExecutionTimeLimit := "PT0S"     ; Never stop it
            td.Settings.MultipleInstances := 2           ; Don't start a second copy
            td.Settings.Priority := 4                    ; Normal priority (default is below normal)
            trigger := td.Triggers.Create(9)             ; At log on
            trigger.UserId := user
            action := td.Actions.Create(0)               ; Start a program
            if A_IsCompiled {
                action.Path := A_ScriptFullPath
            } else {
                action.Path := A_AhkPath
                action.Arguments := '"' A_ScriptFullPath '"'
            }
            action.WorkingDirectory := A_ScriptDir
            root.RegisterTaskDefinition(StartupTaskName(), td, 6, user, , 3)
        }
    } catch as e {
        MsgBox("Couldn't change the startup setting:`n`n" e.Message, AppName, 48)
    }
    UpdateTray()
}

; ==============================================================================
; TRAY ICON  (built into this file, so the script works on its own anywhere)
; White lines on a dark taskbar, black lines on a light one; faded when paused.
; ==============================================================================
RefreshIcon(*) {
    try TraySetIcon("HICON:*" TrayIcon(IsPaused, TaskbarIsDark()), , true)   ; true = keep our icon even while suspended
}

TaskbarIsDark() {
    try return !RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme")
    return true
}

; Windows broadcasts this when the theme (light/dark) changes
OnThemeChange(wParam, lParam, msg, hwnd) {
    SetTimer(RefreshIcon, -300)
}

TrayIcon(paused, dark) {
    static cache := Map()
    key := paused "|" dark
    if cache.Has(key)
        return cache[key]
    data := IconData(paused, dark)
    want := SysGet(49)                 ; Tray icon size for the current display scaling
    best := 0
    for size in data                   ; Sizes are sorted: take the first one big enough
        if (size >= want) {
            best := size
            break
        }
    if !best
        for size in data
            best := size
    b64 := data[best]
    DllCall("crypt32\CryptStringToBinary", "str", b64, "uint", 0, "uint", 1, "ptr", 0, "uint*", &n := 0, "ptr", 0, "ptr", 0)
    png := Buffer(n)
    DllCall("crypt32\CryptStringToBinary", "str", b64, "uint", 0, "uint", 1, "ptr", png, "uint*", &n, "ptr", 0, "ptr", 0)
    return cache[key] := DllCall("CreateIconFromResourceEx", "ptr", png, "uint", n, "int", 1, "uint", 0x30000, "int", want, "int", want, "uint", 0, "ptr")
}

; PNG images of the tray icon at several sizes, as text
; d / dp = dark taskbar (normal / paused), l / lp = light taskbar (normal / paused)
IconData(paused, dark) {
    static d := Map(16, "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAFQSURBVDhPrdI7i1RBFATg9Rms+ECFNVkMRHACRQSzxU1lk8VAjBR8gIIg4mDobzDYX6AmGpqoiS7mgpGYiKCCRooYGnwlPZy5zN5ZHAQruX2qq86p291zc/8InEiys8/PRJItSfbiNVaSbO1r/gocxeMkwWes9jUzgT1Yx9mpBDiFu7jchMUNcAfXkxws7vjUGWBY0dT3G1619Rj4nuTkBmOZByW43yYnOYZPxT1Msg+H8R7vNot+o4Z0sXC7GixOcBeKW+jMtdGupG2cmeCuVNPRfxe3hl/Y1ZkbkmzHlyQ/a8p8O8hquh9HcK/qtQ3mBpzGb9zC7vZgcHWcIMmOFhvP8aHV/QY3S9wdDq7VxAMT3LnSHerMDUmWSnyx6m14WdxwosFT/Jh6A7X5qLq/wddaj4C3+Fjl+b63Q7tOvMCDFheXWio8wxMs9z3/BX8A0uXL7uSTwagAAAAASUVORK5CYII=",
        20, "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAGvSURBVDhPtdQ/qI9RGAfwy02KRZGSQaEMLgk3hSxKGWwMJsUtswy6xeZfIQZluAvTHVhksCkGSqJkYUCUKEYifB6dn+f9dX7n/gaXfOsd3u/3Od/3PN/nnHdk5B+AZRGxsuX/GpjAmZafNbAc+/EWn3EYq9q6P0JEzME4rkUCt7CzrZ01cA43W76PiFiCrRGxodWwHtuwtOLWYcdgZQInSh5VG09wEAfwsOK/4WS7fgCYzOJ3uITpzqAyuo6LeJPvp1qfHrAYX3NidTsTldmRjo+IRXiBn+Uc9o06ZGZl0fmaj4i5+IQvEbGg1nA818ycLMZSvDFEe4n3xbzmI+Jqrhmv+U4cxV2/MYk1WFg0vMaHUlN2mdpR/MhBzWv9esBUxvUoIvZ12dSGJV/sxf3c3XTr00Neo+942raGV9nyaMM/KO0M/TFExPb84ulWK0cEH8t1a/hjuWZXzXfi6hTvNPzaktWw8MvdTX6s5vvA7Sy4HBGbsBvPM9fCl2nvwUZcSO5eu/M+yhDwuDOojEpOM4BnWNH6DADz895eiYiz2JzPlvKzKBkXDYfag/5f8Qsf84dNUp1UDgAAAABJRU5ErkJggg==",
        24, "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAIuSURBVEhLvZVNiI5RFMdHNL5GGDUiiymEWVBjSmalppiFhYUVBhtmZTZDyWxMoyysp6ZZYGMWko+kZEFplELKYj6KBVFERhLl4/fXeZzn6T7nfSzw5rd56/zOPfe99557n4aGOiFpFrApxusGMB+4EuN1Q9JBSQJ2RvfXSGqUtAu4YcVzgEvA9pj/x0iaDWyQdBiY9uKPbTXAmpj/T9gBS/oArIquBqBZUlOMG94tyyTNC/FGYCiN1QAcAR4BH4E3wFVgq6QFQAtwCphy/wI4C6zOx0taWq7o2L+SdDE9qBzgB/ASeBedYXGgPdYsAfR58jfgKNAGdNoKQrG3wH5J64FuSQ89PgnMjXUzvBOmPLE/euBBMkGp9ewsgNfuulNXACwHvvpWrKzw/V7gaXQGcMHnPx5dhh0M8IlfrIse2OcT3I3OAG6674uuALjlSWMV7oC7exVuR7L6jdEXAF3JPlubHsoHxAnsfgB7gOFkzOVYswQw4InvgR5graQl7uIEcyS1epdddzcNLIp1M/wGPvfEvdF7W5obj84mA5653x19BrAC+O772FLhe9IVRCSdd38iugxbGjBjLSRpc4Uf8QIzkhZX+HH3vdEV2CF50p187z3eBXxODnPULmbiez1uFG9SDf40fPFke8TOAdfywinAE3/kbiex07FmDZK22W0tl8sG3/ffCeBVcHZuZ2Kt3wIstG6QdBI4BmzxeIc/2fadsK/VoD/tbbHGf+cnOC11EeeyYNkAAAAASUVORK5CYII=",
        32, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAOCSURBVFhH7ZZbiJZVFIatLLWSshAEo9QOeKrUkKLLDnSCCuqmKEPNIYuC0jsZrNQO0gm66Ex0tCPddaPmIQODIFNxQNAiBa0Q6iIrHZ8V79+7h/2t/vlnGGqufGCYb6/17rX3v7+11v5GjDjO/wgwBjgv24cNYCbwZLYPG8AdwPfZPmQi4kTgNGAe8A7wKfA88DHwAfAgMDkiTpAeeCMiAjg/xxo0EXEqsAT4EvgBOKig/QEs9bxzgd9sey3HHRQRMQXYXgX/y/+/AK4FnvH4pYi4TItqnn091b6keQ44J6/RLxFxOrDLkz/UAsBZWkSvwhrZbnK2Xw28ChyoF27DNxHxKDAtr9lARyk18En2FYCbgdXAJcBs4D7gPeCnvKoAtqoqNC8iJuR4DYCv+Yfp2VcAHnLgZ5P9bGBNtfDvEXFrrRkQYD/wp7I++wrAYi+wKvsiYiSw1/4l2d8Rl9lRT74w+wudNiB03PYrR+bp3WfNvwAWVEe3plMNR0SXdSuyTwDX6737eb+1y7OuD5UJ8AdwBLiusqul3qBkq2xX6Gi916c8HiNfREzVfGU6sMj6K4FD3sTsEqcB8IgFqzWOiNHAu+VE7OsBtpVn/y/j3eXZYx37ScAox3/A9hfz2i2Atzz3Go/HA8eAn9ULgO+q4JuU/X5+WW258mkjas/dwETgIsebacnGvHYL4HUHuLHYImKSyqrSXABc6ud7rO/2+GIde9WoRqqVl7shImZZv67EawDca8Hb2dcO4H7rn8i+dgCPWb8y+1pExJmllTofRmdNTVUxHcsrIk4G7lZpO8knZ00fev9ArwNPks2dbbluNR07cDnwtJLJm33TlXAVcBvwisetryFgbET8au38vGYDX0K9wB6P9Q2wwxtqUFVBX3ImtOg4xQE2y9Cpr7Twr9UGftTYG3g/Ij4C7lJ+qNR8qZS74HG9Mtv1kaJTUmWsLa0c+MraGXnNBspY4FuL52Z/TZW0bTthwQ3uMPBLaVYdARY68HbVcfYXBroLREScAWwYzEYbqJF40iF/zTwMzEmathtw75B+BbDPmi0DVVUDt9AXSjY5yM7SVIRKy/Zl9Vzg8zRPH7Bja82gcedbqFvNwbYAd6pb+lNNts3ALf77zDa148XqjjnmkFA5AevrX9YfTuIpOcZ/AnC7S0zlqNLTBdOlZqS7xPfDKXnecfrjb+ZL5yGqhOSnAAAAAElFTkSuQmCC",
        40, "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAASBSURBVFhH7Zh5iNVVFMe1PWg3GKxIw1ZbTVtts7H+sJ3A/mijoj+LckkICkqEiCIiCqPtzyyiSCPKLFrIJAqiIiptX2mxzUrNPie+w/fafWd+7808mwGD+fwzb852z7vLuee+UaNG+B8SEXtHxFZZvtkA3AqMzfLNgojYGvgSmJp1w0pEbNn0OQMcFhEBzM66IUMJaA8BE4G7gDeBVcBLwDJgJfA28BDQC+xUfIEbnODLrVH/IxGxM3ANsBT40Amt1WCdAL4CJjnGDlpey8XJeZxNApgGfJwHF0ogIm4BFlSy+4GbgXnAto4xFngm+X4BHJvH6wrgJGC9A26IiEeBOcBc4I5yGoEe4FvgsYjYVTJtBc0ScCfwXZ1cAfgbeAS4ANinfKFB4WXVDCmQZnBytikAY4AJ+my/m4CPckKdAH4BHgCOzPEbAa6141rg0KyvAQ7SlwAeBMZFxHb6C5wD3KfBc0IF4Cngch067dOI2CLHbyQiXnSARVmXiYgDqwFnNOjHl3iVnbbEtGw7aMoS6fRmXSYleFrWi4jYRUkNZDcotNFLsKFKUGhv2ma5/98L2C/bdUQOwDvVgIuzTaaLBCfZZnZEjAZeiYifVS2ybSOeuVUOIu6NiFOyXQbYt0qwN+sLLj1amcmevXX2+RU4INv3Q1eXHdYBZyTdhIg4IQcCDtcdq5rmHKf7zt2mslGNm+orUt3MHpYfBfzgMZfWcfuh2dN023hBJR8PPFkVbBXXd4F7yu2gu9VL9RfwtGWv+wu/Uc3URRGxez0ucIm/mPQTa10Lqvo22lBvXJWZEqAdwLNOUL6PZ30BWOGYxwPb+/OOwGrrr6hzagE4z0Za3p5aDrwGXO8l0bWk+1ZdzArgKu3BssRaSuB81T3gLeBhF+Kjgcu0vPpcCrL35af2nduSVE2awf2zvhOa8Wqipmd9J9zlDDyDPsF9VxIwP+s7Mdgy0wRwYeV7cNa3ANxtw/XA2VnfjnoGO5WZjBqD6hQvy/p+uCt53w6iJUm3VVNUwyqZGoVDqj3Y6xkdLb1OrX3G1bFcC9fY53v51Pq2AGdVs3GMZNrQPiQ/Wf47sMT9n/5/viozS4rMB+RH//+HVqg6vWpif7NuTs6jLdVpXgPsZtlxJekm/B5ZXdfBdugkV2OttGxeSxKdKDPoPrBU/B6XjSf8BLgaeAF4D7hN/aKSs5+66Fm6z12ebrTPQhfvvoPgu/gz+8zKebTF11LZT5dmfRO+BssMnZr1TWhV/IyQT3d9ofeUHPWEHJP1mW7LjB/wr9r+k67eIsJVHwfQbXBitqnpJsGIOAJ4rrKfmW0Ghap6CeJASlT7bmG2HShB4Dr7Li9f3LZdXQj9AM4EPtiY5b+BT092e1a6lreuks+PfOBr4MrabpPxC00Nw+3A5x5DNU+/NKj71uutbpnm69BYPrP6NUFNqX4qubiUryHHt8Y3VTKir0+sccOxUQ78mWd92HADu6hh2bTHFpd6aJnQ7zlTcpxhx4nOiIhz1eIXuVo1FXvd45rxVq8RRmjhHxWonybxi1UVAAAAAElFTkSuQmCC",
        48, "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")
    static dp := Map(16, "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAE4SURBVDhPrdLRS1RhEAXwNaxcpEIT9mVRKYvMKPDJJwVF1IRECCsiAjVLjfD/f/iNjAzL3btiCh74Hu5858x3Zs7tdO6IiJiKiAft+q0QEY+wi35EjLXvbwSeYh3/8C0iZtuc/yIiHuLjtQ7wHB/wOokleIb3WMTjqo3uAEs4wyF+p0Vs46hO1n5iekiYqFdOsZIv1/cXXGC1FjeJA+yPWI+IN/jVtIW31XSywZtPJxExMRAXuV8We43aq7TeJKdD/IiI8YE4kZbwNWeMiBdJqAbHuTg8wXLFtzIkrgYzOULarh1kw6sG6SBHQxdb+HxdAhnRcauWUZ40R8gfp0btNrlJ7uEcL4uYDnbwF+8avE18H3FQl2sl+FT7yH/iT529ivA8k2hrB6g48+VVzGEhXdXsG82U7hWXrHOdoa1pLrYAAAAASUVORK5CYII=",
        20, "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAGwSURBVDhPtZTbS5VREMWPKalh5TWl7KHSEryBckQiEKFEwTiRdrEH837H2//Pb8WS+T722Z0ejocWfC9r7W/2zJqZXam0AKAbeJzz9wbwVtJ8zjcNSY+AN8BP4LekiZYylTQILAGHwDGwAjzPzzUNoCrpY86XADoljQADDbR+a5K6Ck5Sn7n6kwFgFtgFLoELoAaMA2PAOnAe2h4wl/9fB2AGuAG2gIXwx96cxncCLIf2A7j9Z9Aocwf4lZYTI3EUgScLXtJD4Duw7zksAxUAnkUp1ZSX1OZLgG1JHakW9lw17KyNBc5cUq4Bm541B095SR/ss8cn5QvRmayFT7OSeouMJH2zr5IemJP0FJgKGz6bz+PdAXgfJdQkvfYmmE8Cttlf4FV03BYt5XHuEGtkg782KK3MMOUjOzfs73UDhn1joyWPgO5+3UXANHANvEj5QnwS/q2mvL2MzA9z871ubqQbmvIlgE9x46LXDhiNDh9HaZ67l6FVw++1PE4JD6ikL7EtxYo5Mw+81/EggljzmQ1JPXmcOtj42A7P2ILLjGdqyA9DvCzW3klqz///b/gDv6pCKdAxxDIAAAAASUVORK5CYII=",
        24, "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAInSURBVEhLvZVpaxRhEIRj4o33hSiKmhhvRYMfBBVPlFWMxvs+Y7yP/w9PSS21y2zPrqAGC+bLWzPdb1d314yNLSKATfVs0SBpArhYzxcNwH7gE7Crcn8NSeOSdgPXJL0H3gHzwGVgZ33/jyFpiaQNkg4C94CPkm4D08C6+v4/wQ2W9ErS6sq1IGmlpGX1vIfwE+VsHDjZPGsBOAzcAZ4DT4GrwDZJSxN0RtJ94AXwCDgPrG18v2IwYhAtLwBf87hZC8B3lw08BB4Dn/O8td7mc5nNNeYAcnMHfgMcc+Ny8yvAh0ZCVzUlab2nBJgFvrnqKlkfvj0wlwRHKw/cSnCP38DoWRLgSaoaPpbAKuClbz9sAoAjSX63ckb68NOVV64LScuj47xLrzwwGRk6lTMyCD8sc+X68CY6iBs9hJtKghtDOPfB/fEz2uiAHdHYXuLGHZK0MdxAAu+HpH3AmdiDv/m9yQEn8qKl6k6JpQtXE9h/1njKIo+/mxu5mNnAB5mEycrXBE1kf7x4XyTtqXwXnpws02tPVOUbTW4lMCSdzRQdr1wXLi0L5FlvbaS1TnXPerIVvpONPlC5PoBLeanTDOLmpzpbw4Jva1l6fGzaF7MD9D2phViDJfJCuR/n8tPoeY4DdKfMfh9Zrie4x3umxmxB0vaYmpNYUy+P5/tmEtllzbsf5l2x+dM11kjYloG9wCk3Ddia8y3h7D3TvrEtxJXXGP8dvwBb0xOU+jLFOwAAAABJRU5ErkJggg==",
        32, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAODSURBVFhH7Zb5r1RFEIURFRSUICgJD6JRn6jIIvgERRHFKGGLssoiyKqCLG6/+M9/Zb7J6Zc77cy8J0Z+4iSTube7uru66pyqu2LFE/yPqKqnq+qFfvyxoapeqqoP+vHHhqp6Azjbjz8yquqpqnoGmK+qz4HDwD7gizxvH4Yc+AS4C7w4vtO/gHkEdgIngPPABeB+fnfy85AHwD1gh+uAtcBV4Bcd6fddFvQcOA38DvwM/ADcAo4Cc8CHwB/Ax8ArHpp1Wwx9Vf0IXM///ja/LFTVszn814R4I7DaEJsKbRyrqlcTpbmq+hS4FGdvV9U1HcjPSN0EvgH2VtX6/swxGMrc/HA/1+DhwAHZHgffBQ7FiZ8Ghxu128BJYCHrnu/3G0OM78zyVNIBf5mKbnx1oqYTNxOJ14Y2SyKEuyLr+7mGqnoH+M2QTphTMedC1vf6+ZkA3kzYvMG6fr5hlgPCIiQBw5F5YE9v8w/EUDmZM7U9VcPA23Fg4sbAVuB4nr+LYnb3douIdiWNh29p4ympEmfDwHZTiPrQmypDbxr79R6e/20De+uCCtnY9hmDuQrzF3xP6GS1ix7mX2kqJWXl8428m64zPkf3f6ZiyoXmWEvZR/3ZIwAHU9HmfK+q58LgSym9HmR0rHwWI8uwle5A0qVTzZGvq+r9qlrTeBS5anO0P3uE1G5vurWNWXiU1cBmXQth+GLERnk1RYa9FarWOwaFa0OcP9L2G4P5SogO9nOTsJQKehiRODzZvqpWARfj5Y6Wu2kA3nJDN+7nhqiqlZG26bM3TP9ISZPR0Ao2Mkxl2wt8lrDbeBYkkxxID/B9sxUv7/va+vSVy7nYfH/mGGJs1xt9SJg/4FRYbWOSpKrB/5EKqurbkFGCWfm0U/OXjar7AMeybmpdGSEd75pl1Pc4oBSt7YbRKNhq1b69QNLuiYTPAl8mSirjSCvlzYFZvWURkdvdqnq5nxsipJVUEythQ6Rovbg4q7csIhsbxtMu7ucblqOCENvbT2f/JKTwuOj7FJzdfQmd5kBqx64Q1x7gPseXUtUYkns/o1SEh0iqU0ObQSHa1Y1/FXvXSbxDywr9JKTy2fX8QJFw3sTPbTudxLRzHsunmQ1LEmonIf1CWmxg/wnJpfXfzZsc76dXKEHH25yynS23RwXwenqG0rRa2mCMkPK0mW2z8vXrnmAa/gaXwkXl1qLExQAAAABJRU5ErkJggg==",
        40, "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAASMSURBVFhH7ZcJj5RFEIbxRlHkEBTihQKJIiAEI4sHiigoiBpQVBDkUFFETIx//ynzTN5evumd2Z1BSDDyJl92p4/q6jreql616j7+gwDWVNWD/fg9A+BAVT3Rj98T0HLAN8Cz/dxdxdBlVfXA+OwtABuA68Ab/dwdgwrkWwccqqovgTPAZ8Cx/P8V8D6wtaoeaXuBvcBN4NNxqf8SHuKtFRwF/C4AN4A/gN+BX6rq51jIsb+A74CNkfEw8C3wk19VPdefc1tQEHA2SniwSvn52wMPAPuBK1Hunfze21xvUgDHc4kfo6TKb+7PmwsGcw5WmUvAh7HkbuBgy8aqWg18D3xcVY9mzDDwcgeBcyoXGZcGSl4GjlTVK8BTc9GPB8VCKne2qp7p1zQAj3mA/2efFjRb3funro9SIwUHSnp5vWJc/pC4HYXEigB2NctV1fp+foiqejoKHa6qJ6vqIf8CL1XVuzl8kgWvanVgp0lnrC/HAmNIQni7w/1cjyjogVri+QnzKnuii0HdvqVfOzOSqSbDrn6uRxQ0nrTS1n5exPXG6SiLp62bCQNhuviOKCiAfbHyifxe02J3ZgBrgdPhtJtVdbRf02MOBTfm0qNKErcbl7OVPrOxqr6OkCsJ8BXjJJdqCk5dbwKEGTaGG1XOsy54yX79EoSzjDsPe6GbWyuv9YJy2PocNrKgNXfIabpRK0XBxW5G6gLOR8lPhnKXIHFnZlkN9g/GzUCp4HLcrvLW2gWFRinr8LlkqGTtus9z4VMZ9+Kv6qXhuRn7NR5bN5wbQ1jfw1Rg7WD8A+DvCJG3rnXl7rco2hS0Mqigc22de113UpmWOGtz5FvnTUgNs3Oo0xgk1QgyHlZ346eBPXHJNuA94It8ryUGm4s3Z89JLZ0L7gA2+Vf3KqcRckqice9Fdo8pNcQ0C86CLkmmZvEkzGNB6+mSGJwFs9LMJKRRMGyuLhuDIoE/MYuXw6w00yO82LL4WD+/BLGi8XYtHciL3fzjibE1bSxF3u66xeCWoSXSim2SDRYF3aInk0rrne/payq0XDO5gh0Lf+0BLiZDTaSj9of5bTM6yuKMu/d4EkQLWXu9wIKdTmRK1HY5871RBtms4BFnxWp2NtejkJTRaMYDxngwF3TcNW2PMn0G7FBmLt0akunZ2yMWVJjWGjF+XKsSH+lC4HV/hx7espLEeoaFbGAv6eGS9JvZcyi0M3J/Ry8rNiSLSFnSHVppez8/CdkzV5KEFw2FmfcsIjF1IzccK02TMC/N5AEvkRsiZ1pczoxUDG9nHFl3l22H5lEw1GK3rocMpW39mpmQstRqqspa1rz1Qr92JQXzEjw16P+8uAru69fOhSSMjyFv2h7oZuiYEqGMpuCImgZzKt+UGjFBKtb0sjYP8kJ7GXg7ynpz+ctMtUe0HduedkmL++T0jeu4jYUNqnukLSuVa1eM69tCrGFhH7VQ4b2LIWKtN/oG4/7W6lp3ievvCmKZI3Gbrm99opkvT6pMG/dhLn/O9hi/kwj3GaNWng1tXCtbw/NoX747uY//O/4B30OwtRccPx8AAAAASUVORK5CYII=",
        48, "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")
    static l := Map(16, "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAGVSURBVDhPrZI9axRRFIbHj1joujv3nue94yyIRRC0iATBTmIraSRFSBXBD1AQJCRY+hss8gtMGlOmiTYq9oFUwUYEFUylhJQWrhy5O6yzYCL4VjPPnPec99y5RfGPSildKYriVJsfRcdCCD0zewfMFkVxvF3wVwEXJb2oqmoAfDazW+2aQxVj7AJvJd0cSwBclfRE0h0vzIbLwLKZPeh0Ojgry3Jq7AzMbCWl5NF+ShqY2R7wBnA2cAZ8kzT9h9HlU9xsZs98spldAj7lXdd6vV5ZluUFSe+B3bHoZvbQJ4zGApa8aQjh/JCFEBa8LqVUNeZcPJsjzoywu87quv69d2arwEFVVWcac9ZJ4AuwDyzUdX3aD9IbdLvdKGkSeJpXWm2bfYVrkn4Aj83srF8Y4N5IggmPDbw0sw/+3m7wKJ9BczjAfWf9ft+GLMY450zSucbsknQ9/4XFjE4ArzNbGdYBm8D3sTuQP67ne7BtZl/9OU/zJjvAx8zm295G/juBV8BzjxtjvO2pJG1J2gButD3/Rb8ArOFeJF+Nw3gAAAAASUVORK5CYII=",
        20, "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAIHSURBVDhPtZRPqE1RFMYvLym63Xv391v7vJOBQhn4k/BSyEQpAzMGRgplLAO9YuZfIQbKwITRGzDRG5gpBpREyYQB8koUQyLPvVq3fW77bQYe+Wp3zvm+tVfr72m1/gFAHWNcUfJ/DeAwcLbk540QwjJgPzADfJZ0xMxWlnZ/igWSJoAbZjZIZ1rSztJw3gDOA7dLfoS6rjGzrWa2odRijOvNbFtVVTHj1gE75lomACe9HlVVDWKMA0lPgYMhhAPAI+dcA75JOlXen4MQwqQbS3on6bKkKa+NO2mOpJuSLgFvx8fH/ft06WeIdrst4KuZzeTp+Eg0RQeONnyn0+ma2Uvgh8/hyFEDr5lHAFwopIXAJ0lf6rpekgvAiZTRr53t9XprU0q3Sg14Jem9O895SdfTnYmcbzAm6V6MsW9mk5JWV1W11AXgjaQPbuNRuibpmJnNeqNardai0tkQkq6lDj42s31NbXKHXl8z2ws8SOlOlX6GSGv0HXhWpga8TimPFfxDM+v/9sdgZttTdGdKzUdE0kdft5yXdNzvhBB25fwQZrYqjcbdnO/1emuAWdfK4kua9qZ4Q3N+BEl3UpRXgE3Abkkvsjn0bu8BNkq6mGp4v4x8BG+CmT1p1s6fyVEfGL7nGvC82+0uL/2UWGxmvrdXgXOSNvsJIWzxn4XXOGmHykH/r/gJohORTpq6tMcAAAAASUVORK5CYII=",
        24, "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAKvSURBVEhLvZVPiFV1FMffMDFp+ea+9/t+zr28x4MJTNQWBhWErYLAZtHChSvtjxtzlRsLRDdGQYvWQbSY2tQiJBUJpEWBKAQ6CC60gWnRUKA4NBGRMDozcR6/++a9M7jJwS9cHu/3+d1zfufP79xGY/M0ZmbPx8VNU6/X2wqcjeubJjM7XJblGvBGZI+iCUn7zex7M1urH+CMme2Lm/+PxlNKu4F3Jc3lCK57NGb2bNz8SPICm9lfKaVeZBvU6/WSmW2L61lj3W5XU1NTW8K6p+ujsDYqM3vPzGaBv4E7wLl2u7230+k8VVVVaWYfA79kvgDMmNn2+v2iKNqjFtc1JunbqqrWPI91sfw/sAL8LmnRWc5z/zfzReCFaHBEwLG8+b6k91NKz5nZKx7BsEPgbkrpbUm7zGwauJbfu9VoNJ6MdmuNe9i+UdLxCIGrtYOU0kjrNZtNAbfzIaaH2UBlWVbAsqdCUjdyd5qdz0fmAr7O/ERkfXlhJP1jZquSdkYu6c1s4FJkLuBiTtOxyAYCfshGvokspfROZlciM7PXzWzZzFbKstwT+UCSXvMcey4lzZZleaTVavVfiA78fkg6CHxWvwN8F22OCDiVN/4p6S1gR1EULWfRQaPReKIoime8yyRdyIeak9QctbquCeC3vPFQhN6W2cHlyNwZ8GvuogMR9gV0gAfeRX5bI/eIHlYDF/CV85TSycj68tCAJe8i4MXIgc9z+pba7XYRuUeWD3A0soG8SLnVfqpz7/LiA//6aPCCSvrCL+YQP5pv+OrwTNogHw3AvXzSBUlfAufrmVM7yHW6IWkG+HFoXn0SbW6QpFeB+XqI+ZNP97M7AG4Cf9Qscx+En0ZbD1VVVU97N0g6LemDlNLLvi7pJR/Zk5OT/p3wr9WHPto98mjjses/tIXPemT8Du8AAAAASUVORK5CYII=",
        32, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAARLSURBVFhH7VZZqJVVFP69Ntv1nLO+b+3/HLt0zW7RYJZFJD2W0QQV1EtRSVaSRULaW0hz16QJfGjQkLJRk956aTYDgyC1SAgaqKAJoR6aLeM7rB3nbO/1SoNPfvDz/3uttddae+/1rf1X1T78jxgaGjq43W4Pl/K9hlarNdPMRkv5XgPJSwF8Wsr/DQbqup5iZleSXENyPYAHAaxz9+fc/ca6ro+oqmqSjAE8nlLa6e5Hlo72GJ1O5xAAS0i+RfIzAF/LaV3XO/XOTx4DuFnzWq3W4SR/CNnK0u8eIaU0g+RWOXd3OfpVb5KvmdlZJO9rt9saP0zyFAWNedJtC9s89wEzGypjjAt3P5TkhwoO4HkFmDp1qnU6HQUZkI1kJM9XtQM4E8BjAL6Kbe8Gz49k8f0ugNvM7NgyZh+0lQpO8oVSlwHggpTS8mazOYvkbADXkXwawDe9Ceg7xptIjmqeu7dLf30g+U5K6U8zO67UZZjZok6nox26v1c+ODgIAM/2JPEjgIt6bSYEyS8B/FJV1ZRSlwFgYRzR3aWuqqr9SH4SRbikVO4Wopm7/x4rOKrUZ0yQgPyMyodqRD519qXNLiA5PxeRu2sbx+UwyQWRwJ2lTnD3cwBs0rd2NBhza2n3N0QTkj+7+2/ufnaWq6WSPDelNCvLUkpztLVKwMyWmdkcrVQ6AMdoviqd5LXh43R33x5smJ399IHk4qj85RoPDw8fRPIp7UbuBeI3gM3haJuKTOPg+kf5W6vVtldVNXlkZORA+QNwQ/hfUcbuguQT0dHmatxut53kHwC+VS8AsEXOo7DeVPVHIo+oLeejUyIppXUkl5rZYSSPlr+6rmfG3DfK2F0AWBUZnpdldV1PF63y2N1H3P1EfZvZvDiCpRqnlE6IBtNtVGKCWnm+G9z9pEj4leyvDySviQSeLHVjAcD1UYT3lLqxAOD2sL+r1HXRaDSauZWqHlQDpU0vzGx+OJyIXvsDuELUVpHHjTk2zGyuu+/QWTYajemSTZs2DaKPu6/UtpvZaSTvBbAiznQ1yWUAznD3iwE8qnGz2ez+DQEYJPl91MhVZcw+xCW0A8DHIRog+b6qWqvNbIijyizYIuf5yXYK2mg0WnICYEP0lnH7ShexWiXweYgGADzj7msBXK76ILlZlwrJRXEEd+jIQr5euxTMeFk/MHIC4O1I/Pj+iLtiEoD3YmtPLZW9yEU7XifMiAb3E4DvcrPaLUheHVu4VTwu9RkT3QVCq9VqkHxdRzhRon3Qf1707u36m0kp3UTy5MJmzARUvLJXQJJfRPCNE7GqxGR3fygXXCTzQW4qgqgVjeiW3okAXspFG+17jZjQa7PHUOfTkehvJla7EcBl6pZqz1ErGwBcqIfki2Gne2GhumPp8x9BdCL5aqaYnmhYfdSL2lERzyh9/Cdw90uCYqLj4riqF5Bc7e6r3H1eVVUHlPP2YTz8BTtIXpDqFjxiAAAAAElFTkSuQmCC",
        40, "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAVhSURBVFhH7VhrqJRVFJ3UyrB7Z76z1p7x1tA1uva4lT2098Me1g97Spg/emHRz6JMC4SCEiGiiJDC6PUzCzHSiDILK7KQBKmISrOnJT1MzUrNLNawD5w5d7x3rg8wcMHHzJy9zzn724919plSaT/+hyiK4ohSqTQsH99nQPIhkl35+L6CA0l+b2bn5IK9jaE7+d6ESqUyplqt/gvgrly2JyEDhoUQeknOAbACwGoAb5NcAmAVyY9IPgfg4hBCZ5wYQri3VqvJwHeal9xNFEVRJnkHycUAvnCDtsgb2lCfZtZ44tjIkSP1ey3JU7SGmR3q4dX4DpLj8312CQAuJLkmNSY+JGXAgwBmk2yMAXgawANmdk+pVDpYa6goSL4m46Tnn9+FEM7M9xsUSJ5Pcpsbsx3AiwCmA5hhZo/GaqxWqzWS60jOL5fLhU8fKi8BeIzkT9G4+PjvfwC8QHJKrVY7sqenp/FCbcHDutaNW0NybK4T0dHRATM7St81D8D9JL+MXs+NSx/J9ZDcaGbPkDw1X78lSN7pxinXTszlKUIIx/lLPFupVLq7u7uH6xPAVQCe8s1beVAp8QrJm1V0ytNSqTQkX78lACz1ipuXy3IAOFYbSr8oiom5vFarjdJ6WQ6uU37num0DQCNEqt5clkMGxo1DCJfkcqFcLldkVKz2nem1BSW6FtuTBgrKTc+3ZfodQqiTHJ3r9QtNIPlxDBnJhblOjnYNFCcmJ8kBAN41sw1ii1y3Jdxzq91zOwA8CeCCXC+HmfVEA3V65PIEQwGIjsa697b6XpsAHJMr94GOLvfaVpKXpTLRiJmdmy9kZifpjBWnuQcnVKvVMb29vQdFHXGcNwjD1M0AOEzjAE4j+YvvuThdtw/cexs8BLOT8VEkXxZhR3Il+QnJJ+LpoLNVc0n+DeBV11sOYA7JD/XCzgjXd3V1Md03hHCj9vSX601lTRDre4VtTxNXNKNzNS6iJxJwPPIAvO4Gau6CVjoeyg+0ZlEUZ9fr9UN8/Q6S611+S2pTE0IIk1xp64gRI2rpuJm9T3Kmh2SKzlszW6ENzew2z8FGiBXKEMI1ZraU5EoAzzsRn25mUxVefY+EPHnyZB2JX/uLzmgyKkXmwaNzeX/wyo9hmpDL+4N3OQN70HNwo7/JrFzeH9qlmVYAcJ0bp1Po+FzeBJKPu/I2AFfm8p0h9eAANNMENQaxikMIS3J5H6grIfmZh1o82GSk2ioA48RhcUyNQlEUJ8QclIHyqIhYclWt5qh5SNcSF5Lc7BX/s88ZGACuiNUaQjjDh4eEEGaS/M0X/APAIgDz/febCc0simNeIL/67z8VoVi96iUB/O4pNb3Zin4QqxnA5nq9HjRWFMVZaWufUofr6j6yPuVBjedz/BowNe6l+4vPV/fdHuRBz8MtkfE9tKKNl/wKcDvJt0h+SvJh9Ysyzj01nuQ0neckRU/3+Zy5ZrY8KQSdxd/4XtOaregHOpaUT5oYQrgpl7eCjsGkSC7K5a2gqIjSfM7g+kLlj7/ZKhVOLs+xCzSjC/x7Ht6vBnUXEZz1d7iRK0mel+ukGIyBZnYyyTdi/pK8NtdpC2L1mNwehpVmprybm+sOZCCAu33uMrVxSXEN6kDoA5KXm9nnaUW6wZemeiGEwxMDm+66bnx+yf+B5K2p3u5geLVanQTgEZLfeljEefqnYbQIWC1TUiSzVDQaV/j0b4LP2aR+08xu6OzsbNDXHodfL39M8kd/YTT6xPTxtqsx7np/hRCavL7XoAbWzObFsMUcdV5cKD7MXkD/54zL19nr0F2X5EQAV6vFj+Nq1UT2Osfl8eZZ+7EfTfgPLk8RIdJ1ebEAAAAASUVORK5CYII=",
        48, "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")
    static lp := Map(16, "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAF2SURBVDhPrVLvS1RRFLwrmYXY8u6ZOfft8mjFnmKbGPTJTwqF6BoUgaQSEVS6pSL+/59i4u7y9geyQQP3w5t7zrlzZl4I/4h2u12EEJam+UXxGMD7GGMVQmhNXz6IGOMzM3sL4A7ARVEUz6drFsEygJO5CrrdrpF8DWBLheKKomi7+26M8WVd1yvi5nqQUnpF8hrAd3cfSiLJYwA/dMxsSPJbVVVxolHQKyR/u/ueXtY3gDMA9wD2ZVxKaRXAZ3f/NCPdzLYBXDZllWXZ11A1jriU0rqU9Hq9J+NmQYZItrunEQdgU9KbxVJI8msI4dG4OaMF4Fw7uvuGCvKAnzLOzNYAvFF8ec1JdDodaIUYYz+7r4F/B2QFS1VVPSV5RPJ0JgFFpOImpygBXDVX0I8jDzSsWavdEskbki8yJQUDkrcppZ1G3aGZfZlRIAA4UIOZfch+XLv7r3w+KkI9oiSme8fIcQ6UfVmWPZK1VGl3d3/XTOm/4g88qTWYy3GLlQAAAABJRU5ErkJggg==",
        20, "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAHwSURBVDhPtVTZihRBEKxZxQu17cqIrOmxZVDHg/ECRRERFkFFQVnx1gfvXU+8/v9BYqluemvHh3UxoF8iq7IyIzM6hG2gbdu9Znag5P8ZAE4CuFTyW0bTNPtIHgfwnORrMzu9rUqbpgGAZQCrZvaR5G0zm5Tntgwzu+zuN0u+x2w2201yPJlMrIy1bRsVm06nezquqqpa3MaTGSQvkHwL4DvJb+6+AuAEyRmAeyS/KgbgHYCL5f0NcPfzAH4BeJFSuiJ93F3afNbn7p/M7EaMUbFnAH7/NWlu842ZvRy2o5Vw9zUlTimd6fj5fL4LwFMA77WHfaIOKSVXKxK4CI30CMlXIYSdw4DkAfBj4WSzsF/UUhkj+Vi7puQFf106a32GfIcRgLvSSS9XVXWoq4jkE+kaQlgSV9d1lVI6q90zs/uZ3wyS13ILK+5+TE7IfJdwJH1TSkc18Tzt5TLPOnRZApN8uKC1YYU9VB2AtYV2c/eUX9xkciXUYMqH3P0cgJ8xxsNDfh0xxoNZvztDXlqqcvm1FF920yA10CHfw91v6UV3vyrbxRhbTVjiqzXtXV3XRxTTeklvDbLM00ML6u4P5JaBxVa18NmOH5Qkx3TmEcn9ZZ4SS3KHdkwWU5v6xuMx9WNQZYqZ2akQwo7y8n/DH6qoUv8W0jF0AAAAAElFTkSuQmCC",
        24, "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAJ9SURBVEhLvVVpTxRREBwuUaO7znRVz+y6isqqiFeU+MFEjRfRqBFBxRMPDvFE+f9fTJG3m91mwwchVjLJ5NWb7tf9qmuybA/RarWKuLaXGDGzO3FxzwDgNMnveZ4fi9xuMJzn+XGSDwB8AbAKYM3d7xVFcTRu/hcM1ev1I2Y2RfIFyW/u/gzAmaIoanHzrlCr1QqSnxqNxsHIbcPExMT+LMvG4noHiR8Jy8MAroS1flRVNe3u8ySX3P2du8+WZelZlo0qKIAZki9JfgDwGsAtMzvcE2K8570PQ2Z2m+QvPbosM1sH8FtlA3gF4A3JH3oArKjfiV9qNpsWA/ZBJ0+Bl939oi5OJ3f3++7+tZNQVZFs53lel0rcfQ7Ahqoe0LIuhkguKEFZlhciaWZPUzVrUXrtdnvczN6qqsh10Wq1DpD8qNMPUkBZludT655HTtA9ANhU5ZHbwvT09D71USdU6ZEnOak2AHgUOUFCAPBHbY5cF2kSN3TRA7h2SvA4cmpLmt5VzUHkuzCzpiqQl5jZXFVV5+r1ei5uQIIxdz/l7tdlD+mbnU2O5GVtVKs6KlHrEhcTDJM8lFQ2m75b2GkwNYGLSeOTkRyQoBdSoAbvZ1mWJyK5BSlHw0TysxQV+Z5LHpRA/I2kokuR62DMzGQL64MmUr1Wde7+Psuyrbb1QurSRJvZ2ch1YWZ3tSlJsRtEl5+sYkUH0GnVlh5+SuuaoeBJ/ZA1qEXJLhYB3NRPo8dzljsqk98rEcmHacLVvpkYcxtIVjK1lGRTw5M0/iRVMJ9MTwHFq2J51LUYayeMlmV5EsBVXVpVVdRio9GAOHmP/lY6sSxElccA/x1/ATATcyX9VS9nAAAAAElFTkSuQmCC",
        32, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAP4SURBVFhH7VZrb1NHEHUIrxYS2ztnZn2DZatgCg0UCE6BhoIbqoLCQxQoBEjLs2khlEKBL/331bFm0fXi3ASq8okjXdl3d+7u7Mw5M1urfcL/i0lV3Z0PfjTU6/UmgH4+/tFgZntV9ed8/L9golarbVXVnoh8LyLnQggnRGTR/8+WQ66qp1V1TUSmRpd5P0ya2dcALgO4BeC2qj7356k/awD+UtU/Y4yH+VGMcZeq3lPVZ3QkX3RToOeqeh3AKzN7oqr3AfwGYElEZkTkGxF5bWbftlot5ab8LoSwh6EH8LuqPuRvCOFkmt8stvnmLxnimZkZ6fV6OzzETEWNY0VRdBglOqSq34nIXToLYFVVH9ABf54CeCwiVwEcr9frjXzDETCUPDlzm88lNJvNjqoukO10JoTwFYCBO/FH2tyjtioiV0Rknt+12+3P8vVGQGN6XeWpk+4fpqI8zkgxanSCp2YkGo1Gt2yzIUg4Vf11MBhszecSROQggL8Z0nyOaVLVmyRrjPFQPlkJVd3HsPEEIYTpfD5hAwd4iD4J6BWxB2Aut3kHNKScPGfnqjQsIgfcgbELhxDaAC7xP4BlM3utqkdzu7dw7ZI0q5RSGifJyPbp6elQsrVms0mivuBJKUOe1O0b3Jy/AL5M9qwLIvJkampK0jojYK6c+fM+NOmspqxeeC24Til5AaJMH5nZVWf9DZcZ9f+G0XTJDh1LKTOzU6M7OwCcYUWjpvne7XZ3ksGUlZdeLk59s/ItxRhPeKVbYLroVHJEVc+r6rGiKD5PPOp0Ok2vB0v53kOwZPKkDF9pbDdlld65GDXvcyTWq5TXdrsdXLbDQpV6R3rnPJ1X1QtpvREwX06qM/ncOGykghyMCB2ust8O4A69JMFS7tYDgP0egWP5XIYtlLaZMX2sjutfUph/5tkr2NCQKaDXAM4y7GQ8iRpCOOUcYA+YB1C0Wq0u350faaNtZrbi4Scx10e/32cTul+6SEyY2TURecPGRJJ6s2H7TSr4yR2hMp57A2OXXJmdnd3ORQBc5HdVdWUI73jsYjd9aMKluOgVklFgq+2zF3gdmKOEOS4iP3gxW3CyDUt5cqCqt7yF63ytKArkc2U4aUmqsZUwgVJkpMiv5FAlfOGXDDE/zucTNqMCpoCn34j974CFx8x4E/rFCXU06b9kM9YBks/Mjjhxl31z9oRKVeWYiDGedEWwfJJU18oGqRBxs/K4mf1IEvp3JOxgU6EfB1Y+dj1eUJxwl3jdZrV0YrJzXuQthw9JSDsSkjckVr98zQ+C53LJnRjK0W/GVMwzHx/OuWyr5fahiDF+4T1jwHsjW7XfC856M2P73ZJ/9wnr4V/k8sVA5o9mPgAAAABJRU5ErkJggg==",
        40, "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAUMSURBVFhH7ZeLTxVXEMYXFe0DuOyemTn3Eip9oEmxT9OmtbW1D1tbpFoi+KiCiIqCUps0/f+b32YOXQ5w2UsxsalfsoF79jy+ncc3c4riJf6DiDG+XhTFkXz8hUEI4ZNer/daPv6i4IiIXDezmL943mi6bKjx/zaMjY1Vqvokxvhe/u4wAYGhTqczrqpfmNmvqrogIrOqeon/zWxeRL4OIUwURTGcFqrqhyLyTER+3r7lv8cwX83GEPBnWVU3ReR3VX0aQngkImtYiLEQwp8icmtiYiL4HsdE5KaIPORR1W52xsHARiJyAxJOZtMfft8k6EXkrIjch5yqfslvrJVcT1Ko6k9m9khVV5zkrRij5ecNBILZD36qqvdCCN9iSTN738w+T9k4NTX1SgjhNzP7oSiK4758iI9jXgjhtpO7508iuRpC+M7M3g4hjA4qP8exkFvqRq/Xk3xCwvT09Ak/ALAOi173tX+461caBBPJ+3iFuFTVJeK2ERL9EWM8kyzX6XTK/H0TZVl2ICQiF1R1pCiKo/wdHx+fUtXzHE6M7mLBB1hdRE6TdJ5Qe6rANpAQfF23272Qv8vhBB+a2bOqqibz95AVkcvNGMTtItLL57aGZ+omlszf5XCCqxBwadkNx4nTlMV95rVCvRkuPkSCeOVj18HL/KYuN2K3HaqqGlPVawQ2m5nZxXxOjrYER0dHg390XUkgSkwOUvpOqOqiZx/ycr5NnPBRieA+84dQBoi6NpIwJOIyH5lP3gE0y6vDalmWbzTfuWW7+UbIAlnulqgtSM1tahpudCsNNbsZpMvM7jjJH5v77sDMzAxxd9tL1dk0Tga6FKy627HUvJmdY1MvcbNmxtoVn7sWQvjFRfqKayDV5x281DyXMVVdx2MuNbsD6/hhq1grjYcQvlHVv3wTdOtxs9yFEDYgmghSGVyYsUqat66qGzHGOfb0EnfMjxj2hMQwp7cI5XBRZaNlSlca73a7jF8zsw9wSYzxLRH5ysyu8lRV9a67v3Yxh7OXiMxhaT5QRE51u13lL+71qpQEmZJI3G9SQv9hlGEvC7ZBM0n6ZfEeaGdB6qm7aVsMtkFbmdkNNAqEDeHTNwZBWZYE/q5Z3A8DyMw2oACNLL6Uv98BrOjx9tjM1nq93snm+8nJyVeJMb+Z1eCrvbuuYxCCTUsQz8SfNxFbgJxnPWfdyeVrT2C5ZHI29uEhkkRV73qGLlNh6A/9N81okpmLrGWMBOFw76D5gHN0OmzoQr008B3Fs3adjbEoY1jNu2niE0JISy0zPjbrGlrroEsR3TVz0hr25Bpwyo8ie+uGpG/25sCCLjd3k+LjWifxPS6sqmrGL0mLIYRPvZJADiJd7yUXXKQ/Yo1fsOYb7t+SlzYNyRYoS14jsdJ0/n43sGbQJHFdfODS1mrNFogfd89icnM/HEBmuMDPeYgspLhsDZTeA/2J192+7dAgBMlev77ioXUqUz6nFQjmVFO9Bl/18kUmbsN+BMuy5CZ4JfV/nkAbNLD53IFAwvjtjEahvqCToTkJkikRbEhTDcgnUkkJ/D6yd1kbEEdjjG/GGD9zsrhmqSzLM94kjJBMtEtkMWXSE23EGwuurhvIlrdo023i+kDAGl7YUwtFn4d4c6PDvfWTxv1/QoQL+g7XPxdgGXo+dxsk6z7RKwc6udoY52I+2/oyfpjAjcQolcdb/BpYuSzLk/SE+3YnL/F/x99vkyViDbb8MgAAAABJRU5ErkJggg==",
        48, "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")

    return dark ? (paused ? dp : d) : (paused ? lp : l)
}
