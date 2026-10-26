//go:build windows

package main

import (
	"math"
	"syscall"
	"unsafe"
)

// Win32 bindings, loaded by name: no cgo and no dependencies. Only what the app calls.

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	comdlg32 = syscall.NewLazyDLL("comdlg32.dll")
	comctl32 = syscall.NewLazyDLL("comctl32.dll")
	psapi    = syscall.NewLazyDLL("psapi.dll")

	pRegisterClassExW              = user32.NewProc("RegisterClassExW")
	pCreateWindowExW               = user32.NewProc("CreateWindowExW")
	pDefWindowProcW                = user32.NewProc("DefWindowProcW")
	pDestroyWindow                 = user32.NewProc("DestroyWindow")
	pGetMessageW                   = user32.NewProc("GetMessageW")
	pTranslateMessage              = user32.NewProc("TranslateMessage")
	pDispatchMessageW              = user32.NewProc("DispatchMessageW")
	pPostQuitMessage               = user32.NewProc("PostQuitMessage")
	pPostMessageW                  = user32.NewProc("PostMessageW")
	pSendMessageW                  = user32.NewProc("SendMessageW")
	pShowWindow                    = user32.NewProc("ShowWindow")
	pIsWindowVisible               = user32.NewProc("IsWindowVisible")
	pIsWindow                      = user32.NewProc("IsWindow")
	pSetForegroundWindow           = user32.NewProc("SetForegroundWindow")
	pGetForegroundWindow           = user32.NewProc("GetForegroundWindow")
	pGetWindowThreadProcessId      = user32.NewProc("GetWindowThreadProcessId")
	pAttachThreadInput             = user32.NewProc("AttachThreadInput")
	pBringWindowToTop              = user32.NewProc("BringWindowToTop")
	pSetFocus                      = user32.NewProc("SetFocus")
	pUpdateLayeredWindow           = user32.NewProc("UpdateLayeredWindow")
	pRegisterHotKey                = user32.NewProc("RegisterHotKey")
	pUnregisterHotKey              = user32.NewProc("UnregisterHotKey")
	pSetTimer                      = user32.NewProc("SetTimer")
	pKillTimer                     = user32.NewProc("KillTimer")
	pLoadCursorW                   = user32.NewProc("LoadCursorW")
	pSetCursor                     = user32.NewProc("SetCursor")
	pGetCursorPos                  = user32.NewProc("GetCursorPos")
	pMonitorFromPoint              = user32.NewProc("MonitorFromPoint")
	pGetMonitorInfoW               = user32.NewProc("GetMonitorInfoW")
	pGetDpiForWindow               = user32.NewProc("GetDpiForWindow")
	pSetProcessDpiAwarenessContext = user32.NewProc("SetProcessDpiAwarenessContext")
	pCreatePopupMenu               = user32.NewProc("CreatePopupMenu")
	pAppendMenuW                   = user32.NewProc("AppendMenuW")
	pTrackPopupMenu                = user32.NewProc("TrackPopupMenu")
	pDestroyMenu                   = user32.NewProc("DestroyMenu")
	pGetKeyState                   = user32.NewProc("GetKeyState")
	pGetAsyncKeyState              = user32.NewProc("GetAsyncKeyState")
	pMapVirtualKeyW                = user32.NewProc("MapVirtualKeyW")
	pSetWindowsHookExW             = user32.NewProc("SetWindowsHookExW")
	pUnhookWindowsHookEx           = user32.NewProc("UnhookWindowsHookEx")
	pCallNextHookEx                = user32.NewProc("CallNextHookEx")
	pMessageBoxW                   = user32.NewProc("MessageBoxW")
	pTrackMouseEvent               = user32.NewProc("TrackMouseEvent")
	pFindWindowW                   = user32.NewProc("FindWindowW")
	pRegisterWindowMessageW        = user32.NewProc("RegisterWindowMessageW")
	pGetSystemMetricsForDpi        = user32.NewProc("GetSystemMetricsForDpi")
	pGetDpiForSystem               = user32.NewProc("GetDpiForSystem")
	pGetDC                         = user32.NewProc("GetDC")
	pReleaseDC                     = user32.NewProc("ReleaseDC")
	pDestroyIcon                   = user32.NewProc("DestroyIcon")
	pGetWindowRect                 = user32.NewProc("GetWindowRect")
	pSetWindowPos                  = user32.NewProc("SetWindowPos")

	pGetModuleHandleW   = kernel32.NewProc("GetModuleHandleW")
	pCreateMutexW       = kernel32.NewProc("CreateMutexW")
	pNormalizeString    = kernel32.NewProc("NormalizeString")
	pGetCurrentThreadId = kernel32.NewProc("GetCurrentThreadId")
	pCreateActCtxW      = kernel32.NewProc("CreateActCtxW")
	pActivateActCtx     = kernel32.NewProc("ActivateActCtx")

	pCreateCompatibleDC = gdi32.NewProc("CreateCompatibleDC")
	pCreateDIBSection   = gdi32.NewProc("CreateDIBSection")
	pSelectObject       = gdi32.NewProc("SelectObject")
	pDeleteObject       = gdi32.NewProc("DeleteObject")
	pDeleteDC           = gdi32.NewProc("DeleteDC")
	pBitBlt             = gdi32.NewProc("BitBlt")

	pShellNotifyIconW     = shell32.NewProc("Shell_NotifyIconW")
	pShellExecuteW        = shell32.NewProc("ShellExecuteW")
	pSHFileOperationW     = shell32.NewProc("SHFileOperationW")
	pGetOpenFileNameW     = comdlg32.NewProc("GetOpenFileNameW")
	pTaskDialogIndirect   = comctl32.NewProc("TaskDialogIndirect")
	pGetProcessMemoryInfo = psapi.NewProc("GetProcessMemoryInfo")
)

const (
	wmDestroy          = 0x0002
	wmActivate         = 0x0006
	wmClose            = 0x0010
	wmNull             = 0x0000
	wmSetCursor        = 0x0020
	wmKeyDown          = 0x0100
	wmKeyUp            = 0x0101
	wmChar             = 0x0102
	wmSysKeyDown       = 0x0104
	wmSysChar          = 0x0106
	wmCommand          = 0x0111
	wmTimer            = 0x0113
	wmMouseMove        = 0x0200
	wmLButtonDown      = 0x0201
	wmLButtonUp        = 0x0202
	wmRButtonUp        = 0x0205
	wmMouseLeave       = 0x02A3
	wmNCHitTest        = 0x0084
	wmHotKey           = 0x0312
	wmDpiChanged       = 0x02E0
	wmDisplayChange    = 0x007E
	wmUser             = 0x0400
	wmApp              = 0x8000
	wmAppTray          = wmApp + 1
	wmAppShow          = wmApp + 2
	wmAppRun           = wmApp + 3
	wmAppRender        = wmApp + 4
	wsPopup            = 0x80000000
	wsExLayered        = 0x00080000
	wsExToolWindow     = 0x00000080
	wsExTopmost        = 0x00000008
	swHide             = 0
	swShow             = 5
	swShowNormal       = 1
	htClient           = 1
	htCaption          = 2
	mfString           = 0x0
	mfPopup            = 0x10
	mfSeparator        = 0x800
	mfChecked          = 0x8
	mfGrayed           = 0x1
	tpmReturnCmd       = 0x100
	tpmRightButton     = 0x2
	ulwAlpha           = 0x2
	modNoRepeat        = 0x4000
	idcArrow           = 32512
	idcHand            = 32649
	waInactive         = 0
	tmeLeave           = 0x2
	whKeyboardLL       = 13
	smCxSmIcon         = 49
	errorAlreadyExists = 183
	swpNoSize          = 0x1
	swpNoZOrder        = 0x4
	swpNoActivate      = 0x10
)

type point struct{ X, Y int32 }
type size struct{ CX, CY int32 }
type rect struct{ Left, Top, Right, Bottom int32 }

type msg struct {
	Hwnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      point
	Private uint32
}

type wndClassEx struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   uintptr
	Icon       uintptr
	Cursor     uintptr
	Background uintptr
	MenuName   *uint16
	ClassName  *uint16
	IconSm     uintptr
}

type monitorInfo struct {
	Size    uint32
	Monitor rect
	Work    rect
	Flags   uint32
}

type bitmapInfoHeader struct {
	Size          uint32
	Width         int32
	Height        int32
	Planes        uint16
	BitCount      uint16
	Compression   uint32
	SizeImage     uint32
	XPelsPerMeter int32
	YPelsPerMeter int32
	ClrUsed       uint32
	ClrImportant  uint32
}

type blendFunction struct{ BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat byte }

type notifyIconData struct {
	Size            uint32
	Wnd             uintptr
	ID              uint32
	Flags           uint32
	CallbackMessage uint32
	Icon            uintptr
	Tip             [128]uint16
	State           uint32
	StateMask       uint32
	Info            [256]uint16
	Version         uint32
	InfoTitle       [64]uint16
	InfoFlags       uint32
	GUIDItem        [16]byte
	BalloonIcon     uintptr
}

type trackMouseEvent struct {
	Size      uint32
	Flags     uint32
	Track     uintptr
	HoverTime uint32
}

type kbdLLHook struct {
	VK, Scan, Flags, Time uint32
	ExtraInfo             uintptr
}

type openFileName struct {
	StructSize    uint32
	Owner         uintptr
	Instance      uintptr
	Filter        *uint16
	CustomFilter  *uint16
	MaxCustFilter uint32
	FilterIndex   uint32
	File          *uint16
	MaxFile       uint32
	FileTitle     *uint16
	MaxFileTitle  uint32
	InitialDir    *uint16
	Title         *uint16
	Flags         uint32
	FileOffset    uint16
	FileExtension uint16
	DefExt        *uint16
	CustData      uintptr
	Hook          uintptr
	TemplateName  *uint16
	Reserved      uintptr
	Reserved2     uint32
	FlagsEx       uint32
}

type shFileOp struct {
	Wnd     uintptr
	Func    uint32
	From    *uint16
	To      *uint16
	Flags   uint16
	Aborted int32
	Mapping uintptr
	Title   *uint16
}

type memoryCounters struct {
	CB                         uint32
	PageFaultCount             uint32
	PeakWorkingSetSize         uintptr
	WorkingSetSize             uintptr
	QuotaPeakPagedPoolUsage    uintptr
	QuotaPagedPoolUsage        uintptr
	QuotaPeakNonPagedPoolUsage uintptr
	QuotaNonPagedPoolUsage     uintptr
	PagefileUsage              uintptr
	PeakPagefileUsage          uintptr
	PrivateUsage               uintptr
}

func wstr(s string) *uint16 {
	p, _ := syscall.UTF16PtrFromString(s)
	return p
}

// wstrs is a double-null-terminated list, as file dialogs and SHFileOperation take.
func wstrs(parts ...string) *uint16 {
	var buf []uint16
	for _, p := range parts {
		u, _ := syscall.UTF16FromString(p)
		buf = append(buf, u...)
	}
	buf = append(buf, 0)
	return &buf[0]
}

func f32(f float32) uintptr { return uintptr(math.Float32bits(f)) }

func loword(v uintptr) int32 { return int32(int16(v & 0xFFFF)) }
func hiword(v uintptr) int32 { return int32(int16((v >> 16) & 0xFFFF)) }

func keyDown(vk int) bool {
	r, _, _ := pGetKeyState.Call(uintptr(vk))
	return int16(r) < 0
}

func asyncKeyDown(vk int) bool {
	r, _, _ := pGetAsyncKeyState.Call(uintptr(vk))
	return int16(r) < 0
}

func messageBox(owner uintptr, text, title string, flags uintptr) int {
	r, _, _ := pMessageBoxW.Call(owner, uintptr(unsafe.Pointer(wstr(text))), uintptr(unsafe.Pointer(wstr(title))), flags)
	return int(r)
}

// normalizeNFC composes text so one typed letter is one character, as Swift's Character comparison assumes.
func normalizeNFC(s string) string {
	src, _ := syscall.UTF16FromString(s)
	n, _, _ := pNormalizeString.Call(1, uintptr(unsafe.Pointer(&src[0])), uintptr(len(src)-1), 0, 0)
	if int32(n) <= 0 {
		return s
	}
	dst := make([]uint16, n)
	n, _, _ = pNormalizeString.Call(1, uintptr(unsafe.Pointer(&src[0])), uintptr(len(src)-1), uintptr(unsafe.Pointer(&dst[0])), n)
	if int32(n) <= 0 {
		return s
	}
	return syscall.UTF16ToString(dst[:n])
}
