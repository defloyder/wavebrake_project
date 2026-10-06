package main

import (
	"errors"
	"syscall"
	"unsafe"
)

// Plain Win32 calls through syscall — no extra Go modules.

var (
	shell32  = syscall.NewLazyDLL("shell32.dll")
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	crypt32  = syscall.NewLazyDLL("crypt32.dll")

	procIsUserAnAdmin      = shell32.NewProc("IsUserAnAdmin")
	procShellExecuteW      = shell32.NewProc("ShellExecuteW")
	procMessageBoxW        = user32.NewProc("MessageBoxW")
	procCreateJobObjectW   = kernel32.NewProc("CreateJobObjectW")
	procSetInformationJob  = kernel32.NewProc("SetInformationJobObject")
	procAssignProcessToJob = kernel32.NewProc("AssignProcessToJobObject")
	procOpenProcess        = kernel32.NewProc("OpenProcess")
	procLocalFree          = kernel32.NewProc("LocalFree")
	procCryptProtectData   = crypt32.NewProc("CryptProtectData")
	procCryptUnprotectData = crypt32.NewProc("CryptUnprotectData")
)

func isAdmin() bool {
	r, _, _ := procIsUserAnAdmin.Call()
	return r != 0
}

// shellExecute runs ShellExecuteW; verb "runas" asks UAC for elevation.
func shellExecute(verb, file, params string) error {
	v, _ := syscall.UTF16PtrFromString(verb)
	f, _ := syscall.UTF16PtrFromString(file)
	var p *uint16
	if params != "" {
		p, _ = syscall.UTF16PtrFromString(params)
	}
	r, _, _ := procShellExecuteW.Call(0, uintptr(unsafe.Pointer(v)), uintptr(unsafe.Pointer(f)), uintptr(unsafe.Pointer(p)), 0, 1)
	if r <= 32 {
		return errors.New("ShellExecute failed")
	}
	return nil
}

func messageBox(title, text string) {
	t, _ := syscall.UTF16PtrFromString(title)
	m, _ := syscall.UTF16PtrFromString(text)
	const mbIconInformation = 0x40
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(m)), uintptr(unsafe.Pointer(t)), mbIconInformation)
}

// killOnCloseJob is a job object that kills its processes when this
// program exits for any reason — sing-box must never outlive it and keep
// the system's routes pointed at a dead tunnel.
type killOnCloseJob struct{ handle uintptr }

func newKillOnCloseJob() (*killOnCloseJob, error) {
	h, _, err := procCreateJobObjectW.Call(0, 0)
	if h == 0 {
		return nil, err
	}
	// JOBOBJECT_EXTENDED_LIMIT_INFORMATION, laid out by hand: Go's own
	// struct alignment on 386 doesn't match the C one. LimitFlags sits at
	// offset 16 on both x86 and x64; the struct is 112 bytes on x86 and
	// 144 on x64.
	size := 144
	if unsafe.Sizeof(uintptr(0)) == 4 {
		size = 112
	}
	info := make([]byte, size)
	const limitKillOnJobClose = 0x2000
	*(*uint32)(unsafe.Pointer(&info[16])) = limitKillOnJobClose
	const jobObjectExtendedLimitInformation = 9
	r, _, err := procSetInformationJob.Call(h, jobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&info[0])), uintptr(size))
	if r == 0 {
		syscall.CloseHandle(syscall.Handle(h))
		return nil, err
	}
	return &killOnCloseJob{handle: h}, nil
}

func (j *killOnCloseJob) assign(pid int) error {
	const processSetQuota, processTerminate = 0x0100, 0x0001
	ph, _, err := procOpenProcess.Call(processSetQuota|processTerminate, 0, uintptr(pid))
	if ph == 0 {
		return err
	}
	defer syscall.CloseHandle(syscall.Handle(ph))
	r, _, err := procAssignProcessToJob.Call(j.handle, ph)
	if r == 0 {
		return err
	}
	return nil
}

type dataBlob struct {
	size uint32
	data *byte
}

func blobOf(b []byte) *dataBlob {
	if len(b) == 0 {
		return &dataBlob{}
	}
	return &dataBlob{size: uint32(len(b)), data: &b[0]}
}

func (b *dataBlob) bytes() []byte {
	out := make([]byte, b.size)
	copy(out, unsafe.Slice(b.data, b.size))
	return out
}

// protect encrypts for the current Windows user (DPAPI): the refresh
// token on disk is useless on another account or machine.
func protect(plain []byte) ([]byte, error) {
	var out dataBlob
	const cryptProtectUIForbidden = 0x1
	r, _, err := procCryptProtectData.Call(uintptr(unsafe.Pointer(blobOf(plain))), 0, 0, 0, 0, cryptProtectUIForbidden, uintptr(unsafe.Pointer(&out)))
	if r == 0 {
		return nil, err
	}
	defer procLocalFree.Call(uintptr(unsafe.Pointer(out.data)))
	return out.bytes(), nil
}

func unprotect(enc []byte) ([]byte, error) {
	var out dataBlob
	const cryptProtectUIForbidden = 0x1
	r, _, err := procCryptUnprotectData.Call(uintptr(unsafe.Pointer(blobOf(enc))), 0, 0, 0, 0, cryptProtectUIForbidden, uintptr(unsafe.Pointer(&out)))
	if r == 0 {
		return nil, err
	}
	defer procLocalFree.Call(uintptr(unsafe.Pointer(out.data)))
	return out.bytes(), nil
}
