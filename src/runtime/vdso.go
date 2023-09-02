/* NOTE(anton2920): it's a pure freebsd sh**t. */

// Copyright 2018 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package runtime

import (
	"runtime/internal/atomic"
	"unsafe"
)

const (
	_VDSO_TH_ALGO_X86_TSC  = 1
	_VDSO_TH_ALGO_X86_HPET = 2
)

const (
	_HPET_DEV_MAP_MAX  = 10
	_HPET_MAIN_COUNTER = 0xf0 /* Main counter register */

	hpetDevPath = "/dev/hpetX\x00"
)

var hpetDevMap [_HPET_DEV_MAP_MAX]uintptr

//go:nosplit
func (th *vdsoTimehands) getTSCTimecounter() uint32 {
	tsc := cputicks()
	if th.x86_shift > 0 {
		tsc >>= th.x86_shift
	}
	return uint32(tsc)
}

//go:nosplit
func (th *vdsoTimehands) getHPETTimecounter() (uint32, bool) {
	idx := int(th.x86_hpet_idx)
	if idx >= len(hpetDevMap) {
		return 0, false
	}

	p := atomic.Loaduintptr(&hpetDevMap[idx])
	if p == 0 {
		systemstack(func() { initHPETTimecounter(idx) })
		p = atomic.Loaduintptr(&hpetDevMap[idx])
	}
	if p == ^uintptr(0) {
		return 0, false
	}
	return *(*uint32)(unsafe.Pointer(p + _HPET_MAIN_COUNTER)), true
}

//go:systemstack
func initHPETTimecounter(idx int) {
	const digits = "0123456789"

	var devPath [len(hpetDevPath)]byte
	copy(devPath[:], hpetDevPath)
	devPath[9] = digits[idx]

	fd := open(&devPath[0], 0 /* O_RDONLY */ |_O_CLOEXEC, 0)
	if fd < 0 {
		atomic.Casuintptr(&hpetDevMap[idx], 0, ^uintptr(0))
		return
	}

	addr, mmapErr := mmap(nil, physPageSize, _PROT_READ, _MAP_SHARED, fd, 0)
	closefd(fd)
	newP := uintptr(addr)
	if mmapErr != 0 {
		newP = ^uintptr(0)
	}
	if !atomic.Casuintptr(&hpetDevMap[idx], 0, newP) && mmapErr == 0 {
		munmap(addr, physPageSize)
	}
}

//go:nosplit
func (th *vdsoTimehands) getTimecounter() (uint32, bool) {
	switch th.algo {
	case _VDSO_TH_ALGO_X86_TSC:
		return th.getTSCTimecounter(), true
	case _VDSO_TH_ALGO_X86_HPET:
		return th.getHPETTimecounter()
	default:
		return 0, false
	}
}

const _VDSO_TH_NUM = 4 // defined in <sys/vdso.h> #ifdef _KERNEL

var timekeepSharedPage *vdsoTimekeep

//go:nosplit
func (bt *bintime) Add(bt2 *bintime) {
	u := bt.frac
	bt.frac += bt2.frac
	if u > bt.frac {
		bt.sec++
	}
	bt.sec += bt2.sec
}

//go:nosplit
func (bt *bintime) AddX(x uint64) {
	u := bt.frac
	bt.frac += x
	if u > bt.frac {
		bt.sec++
	}
}

var (
	// binuptimeDummy is used in binuptime as the address of an atomic.Load, to simulate
	// an atomic_thread_fence_acq() call which behaves as an instruction reordering and
	// memory barrier.
	binuptimeDummy uint32

	zeroBintime bintime
)

// based on /usr/src/lib/libc/sys/__vdso_gettimeofday.c
//
//go:nosplit
func binuptime(abs bool) (bt bintime) {
	timehands := (*[_VDSO_TH_NUM]vdsoTimehands)(add(unsafe.Pointer(timekeepSharedPage), vdsoTimekeepSize))
	for {
		if timekeepSharedPage.enabled == 0 {
			return zeroBintime
		}

		curr := atomic.Load(&timekeepSharedPage.current) // atomic_load_acq_32
		th := &timehands[curr]
		gen := atomic.Load(&th.gen) // atomic_load_acq_32
		bt = th.offset

		if tc, ok := th.getTimecounter(); !ok {
			return zeroBintime
		} else {
			delta := (tc - th.offset_count) & th.counter_mask
			bt.AddX(th.scale * uint64(delta))
		}
		if abs {
			bt.Add(&th.boottime)
		}

		atomic.Load(&binuptimeDummy) // atomic_thread_fence_acq()
		if curr == timekeepSharedPage.current && gen != 0 && gen == th.gen {
			break
		}
	}
	return bt
}

//go:nosplit
func vdsoClockGettime(clockID int32) bintime {
	if timekeepSharedPage == nil || timekeepSharedPage.ver != _VDSO_TK_VER_CURR {
		return zeroBintime
	}
	abs := false
	switch clockID {
	case _CLOCK_MONOTONIC:
		/* ok */
	case _CLOCK_REALTIME:
		abs = true
	default:
		return zeroBintime
	}
	return binuptime(abs)
}

func fallback_nanotime() int64
func fallback_walltime() (sec int64, nsec int32)

//go:nosplit
func nanotime1() int64 {
	bt := vdsoClockGettime(_CLOCK_MONOTONIC)
	if bt == zeroBintime {
		return fallback_nanotime()
	}
	return int64((1e9 * uint64(bt.sec)) + ((1e9 * uint64(bt.frac>>32)) >> 32))
}

func walltime() (sec int64, nsec int32) {
	bt := vdsoClockGettime(_CLOCK_REALTIME)
	if bt == zeroBintime {
		return fallback_walltime()
	}
	return int64(bt.sec), int32((1e9 * uint64(bt.frac>>32)) >> 32)
}
