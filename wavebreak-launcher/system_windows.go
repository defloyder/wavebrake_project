//go:build windows

package main

import (
	"fmt"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

// The machine the launcher runs on: the real CPU architecture (a 32-bit
// launcher on 64-bit Windows still sees "x64"; on ARM64, "arm64") and the
// Windows build.
func detectSystem() System {
	v := windows.RtlGetVersion()
	s := System{
		Arch:  nativeArch(),
		Build: int(v.BuildNumber),
		Name:  windowsName(v.MajorVersion, v.MinorVersion, v.BuildNumber),
	}
	return s
}

func windowsName(major, minor, build uint32) string {
	switch {
	case major == 10 && build >= 22000:
		return "Windows 11"
	case major == 10:
		return "Windows 10"
	case major == 6 && minor == 3:
		return "Windows 8.1"
	case major == 6 && minor == 2:
		return "Windows 8"
	case major == 6 && minor == 1:
		return "Windows 7"
	}
	return fmt.Sprintf("Windows %d.%d", major, minor)
}

const (
	imageFileMachineI386  = 0x014c
	imageFileMachineAMD64 = 0x8664
	imageFileMachineARM64 = 0xAA64
)

func nativeArch() string {
	k32 := windows.NewLazySystemDLL("kernel32.dll")
	// IsWow64Process2 (Windows 10 1511+) names the native machine, ARM64
	// included.
	if p := k32.NewProc("IsWow64Process2"); p.Find() == nil {
		var process, native uint16
		r, _, _ := p.Call(uintptr(windows.CurrentProcess()),
			uintptr(unsafe.Pointer(&process)), uintptr(unsafe.Pointer(&native)))
		if r != 0 {
			switch native {
			case imageFileMachineAMD64:
				return "x64"
			case imageFileMachineARM64:
				return "arm64"
			case imageFileMachineI386:
				return "x86"
			}
		}
	}
	var wow64 bool
	if err := windows.IsWow64Process(windows.CurrentProcess(), &wow64); err == nil && wow64 {
		return "x64"
	}
	return "x86"
}

// installed reads an Inno Setup program from the uninstall list
// (HKLM/HKCU, 64- and 32-bit views): its version and folder.
func installed(appID string) *Installed {
	key := `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\` + appID + `_is1`
	for _, root := range []registry.Key{registry.LOCAL_MACHINE, registry.CURRENT_USER} {
		for _, view := range []uint32{registry.WOW64_64KEY, registry.WOW64_32KEY} {
			k, err := registry.OpenKey(root, key, registry.QUERY_VALUE|view)
			if err != nil {
				continue
			}
			version, _, _ := k.GetStringValue("DisplayVersion")
			dir, _, _ := k.GetStringValue("InstallLocation")
			uninstall, _, _ := k.GetStringValue("UninstallString")
			k.Close()
			return &Installed{Version: version, Dir: dir, Uninstall: uninstall}
		}
	}
	return nil
}

// runInstaller starts a downloaded setup; Inno asks for administrator
// rights itself (UAC).
func runInstaller(path string) error {
	return shellExecute("open", path, "")
}

func launch(dir, exe string) error {
	return shellExecute("open", filepath.Join(dir, exe), "")
}

func uninstall(cmdline string) error {
	exe, args := splitCommand(cmdline)
	if exe == "" {
		return fmt.Errorf("no uninstaller")
	}
	return shellExecute("open", exe, args)
}

func openURL(url string) error {
	if !strings.HasPrefix(url, "https://") {
		return fmt.Errorf("only https links")
	}
	return shellExecute("open", url, "")
}

// splitCommand: `"C:\Program Files\X\unins000.exe" /SILENT` → exe, args.
func splitCommand(s string) (string, string) {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, `"`) {
		if i := strings.Index(s[1:], `"`); i >= 0 {
			return s[1 : i+1], strings.TrimSpace(s[i+2:])
		}
	}
	if i := strings.Index(s, " "); i > 0 {
		return s[:i], strings.TrimSpace(s[i+1:])
	}
	return s, ""
}

func shellExecute(verb, file, args string) error {
	v, _ := syscall.UTF16PtrFromString(verb)
	f, _ := syscall.UTF16PtrFromString(file)
	var a *uint16
	if args != "" {
		a, _ = syscall.UTF16PtrFromString(args)
	}
	return windows.ShellExecute(0, v, f, a, nil, windows.SW_SHOWNORMAL)
}
