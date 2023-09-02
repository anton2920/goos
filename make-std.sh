#!/bin/sh

BUILDDIR=`pwd`/build

VERBOSITY=0
while test "$1" = "-v"; do
	VERBOSITY=$((VERBOSITY+1))
	shift
done

run()
{
	if test $VERBOSITY -gt 1; then echo "$@"; fi
	"$@" || exit 1
}

BuildPackage()
{
	# $1 - package name.
	# $2 - .go source files.
	run go tool compile -o $BUILDDIR/$1.a -trimpath "$BUILDDIR=>" -p $1 -std -c=$GOMAXPROCS -nolocalimports -importcfg $BUILDDIR/importcfg -pack $2

	if test $VERBOSITY -gt 0; then echo $1; fi
}

BuildPackageASM()
{
	# $1 - package name.
	# $2 - .go source files.
	# $3 - .s source files.
	# $4 - (optional) '-+' compile flag for compiling runtime.
	# $5 - (optional) '-compiling-runtime' asm flag for compiling runtime.

	run go tool asm -p $1 -I $BUILDDIR -I $GOROOT/pkg/include -D GOOS_$GOOS -D GOARCH_$GOARCH $5 -D GOAMD64_$GOAMD64  -I $GOROOT/src/runtime -gensymabis -o $BUILDDIR/symabis $3

	run go tool compile -o $BUILDDIR/$1.a -trimpath "$BUILDDIR=>" -p $1 -std $4 -symabis $BUILDDIR/symabis -c=$GOMAXPROCS -nolocalimports -importcfg $BUILDDIR/importcfg -pack -asmhdr $BUILDDIR/go_asm.h $2

	for file in $3; do
		run go tool asm -p $1 -trimpath "$BUILDDIR=>" -I $BUILDDIR -I $GOROOT/pkg/include -D GOOS_$GOOS -D GOARCH_$GOARCH $5 -D GOAMD64_$GOAMD64 -I $GOROOT/src/runtime -o $BUILDDIR/`dirname $1`/`basename $file`.o $file
	done
	run go tool pack r $BUILDDIR/$1.a $BUILDDIR/`dirname $1`/*.o

	run rm -f $BUILDDIR/`dirname $1`/*.o

	if test "$VERBOSITY" -gt 0; then echo $1; fi
}

GOROOT=`go env GOROOT`; export GOROOT
GOOS=plan9; export GOOS
GOARCH=amd64; export GOARCH
GOAMD64=v3; export GOAMD64

GOMAXPROCS=4; export GOMAXPROCS
GOCACHE=off; export GOCACHE

CGO_ENABLED=0; export CGO_ENABLED

run mkdir -p $BUILDDIR

cat >$BUILDDIR/importcfg << EOF
packagefile internal/abi=$BUILDDIR/internal/abi.a
packagefile internal/bytealg=$BUILDDIR/internal/bytealg.a
packagefile internal/coverage/rtcov=$BUILDDIR/internal/coverage/rtcov.a
packagefile internal/cpu=$BUILDDIR/internal/cpu.a
packagefile internal/goarch=$BUILDDIR/internal/goarch.a
packagefile internal/godebugs=$BUILDDIR/internal/godebugs.a
packagefile internal/goexperiment=$BUILDDIR/internal/goexperiment.a
packagefile internal/goos=$BUILDDIR/internal/goos.a
packagefile runtime/internal/atomic=$BUILDDIR/runtime/internal/atomic.a
packagefile runtime/internal/math=$BUILDDIR/runtime/internal/math.a
packagefile runtime/internal/sys=$BUILDDIR/runtime/internal/sys.a
EOF

STARTTIME=`date +%s`

run mkdir -p $BUILDDIR/internal/coverage $BUILDDIR/runtime/internal
run cp $GOROOT/src/runtime/asm_$GOARCH.h $BUILDDIR/asm_GOARCH.h

BuildPackage	"internal/goarch" "$GOROOT/src/internal/goarch/goarch.go $GOROOT/src/internal/goarch/goarch_amd64.go $GOROOT/src/internal/goarch/zgoarch_amd64.go"

BuildPackageASM	"internal/abi" "$GOROOT/src/internal/abi/abi.go $GOROOT/src/internal/abi/abi_amd64.go $GOROOT/src/internal/abi/compiletype.go $GOROOT/src/internal/abi/funcpc.go $GOROOT/src/internal/abi/map.go $GOROOT/src/internal/abi/stack.go $GOROOT/src/internal/abi/symtab.go $GOROOT/src/internal/abi/type.go $GOROOT/src/internal/abi/unsafestring_go120.go" "$GOROOT/src/internal/abi/abi_test.s $GOROOT/src/internal/abi/stub.s"

BuildPackageASM	"internal/cpu" "$GOROOT/src/internal/cpu/cpu.go $GOROOT/src/internal/cpu/cpu_x86.go" "$GOROOT/src/internal/cpu/cpu.s $GOROOT/src/internal/cpu/cpu_x86.s"

BuildPackageASM	"internal/bytealg" "$GOROOT/src/internal/bytealg/bytealg.go $GOROOT/src/internal/bytealg/compare_native.go $GOROOT/src/internal/bytealg/count_native.go $GOROOT/src/internal/bytealg/equal_generic.go $GOROOT/src/internal/bytealg/equal_native.go $GOROOT/src/internal/bytealg/index_amd64.go $GOROOT/src/internal/bytealg/index_native.go $GOROOT/src/internal/bytealg/indexbyte_native.go" "$GOROOT/src/internal/bytealg/compare_amd64.s $GOROOT/src/internal/bytealg/count_amd64.s $GOROOT/src/internal/bytealg/equal_amd64.s $GOROOT/src/internal/bytealg/index_amd64.s $GOROOT/src/internal/bytealg/indexbyte_amd64.s" "" "-compiling-runtime"

BuildPackage	"internal/coverage/rtcov" "$GOROOT/src/internal/coverage/rtcov/rtcov.go"

BuildPackage	"internal/godebugs" "$GOROOT/src/internal/godebugs/table.go"

BuildPackage	"internal/goexperiment" "$GOROOT/src/internal/goexperiment/exp_arenas_off.go $GOROOT/src/internal/goexperiment/exp_boringcrypto_off.go $GOROOT/src/internal/goexperiment/exp_cacheprog_off.go $GOROOT/src/internal/goexperiment/exp_cgocheck2_off.go $GOROOT/src/internal/goexperiment/exp_coverageredesign_on.go $GOROOT/src/internal/goexperiment/exp_fieldtrack_off.go $GOROOT/src/internal/goexperiment/exp_heapminimum512kib_off.go $GOROOT/src/internal/goexperiment/exp_loopvar_off.go $GOROOT/src/internal/goexperiment/exp_pagetrace_off.go $GOROOT/src/internal/goexperiment/exp_preemptibleloops_off.go $GOROOT/src/internal/goexperiment/exp_regabiargs_on.go $GOROOT/src/internal/goexperiment/exp_regabiwrappers_on.go $GOROOT/src/internal/goexperiment/exp_staticlockranking_off.go $GOROOT/src/internal/goexperiment/flags.go"

BuildPackage	"internal/goos" "src/internal/goos/bare.go"

BuildPackageASM	"runtime/internal/atomic" "$GOROOT/src/runtime/internal/atomic/atomic_amd64.go $GOROOT/src/runtime/internal/atomic/doc.go $GOROOT/src/runtime/internal/atomic/stubs.go $GOROOT/src/runtime/internal/atomic/types.go $GOROOT/src/runtime/internal/atomic/types_64bit.go $GOROOT/src/runtime/internal/atomic/unaligned.go" "$GOROOT/src/runtime/internal/atomic/atomic_amd64.s"

BuildPackage	"runtime/internal/math" "$GOROOT/src/runtime/internal/math/math.go"

BuildPackage	"runtime/internal/sys" "$GOROOT/src/runtime/internal/sys/consts.go $GOROOT/src/runtime/internal/sys/consts_norace.go $GOROOT/src/runtime/internal/sys/intrinsics.go $GOROOT/src/runtime/internal/sys/nih.go $GOROOT/src/runtime/internal/sys/sys.go $GOROOT/src/runtime/internal/sys/zversion.go"

# Reimplemented sources.
GO="src/runtime/defs.go src/runtime/env.go src/runtime/lock_sema.go src/runtime/mem.go src/runtime/mem_sbrk.go src/runtime/net.go src/runtime/netpoll_stub.go src/runtime/os.go src/runtime/os2.go src/runtime/os3.go src/runtime/signal.go src/runtime/sigqueue.go"
ASM="src/runtime/memclr.s src/runtime/memmove.s src/runtime/rt0.s src/runtime/sys.s"

BuildPackageASM	"runtime" "$GO $GOROOT/src/runtime/alg.go $GOROOT/src/runtime/arena.go $GOROOT/src/runtime/asan0.go $GOROOT/src/runtime/atomic_pointer.go $GOROOT/src/runtime/auxv_none.go $GOROOT/src/runtime/cgo.go $GOROOT/src/runtime/cgocall.go $GOROOT/src/runtime/cgocallback.go $GOROOT/src/runtime/cgocheck.go $GOROOT/src/runtime/chan.go $GOROOT/src/runtime/checkptr.go $GOROOT/src/runtime/compiler.go $GOROOT/src/runtime/complex.go $GOROOT/src/runtime/covercounter.go $GOROOT/src/runtime/covermeta.go $GOROOT/src/runtime/cpuflags.go $GOROOT/src/runtime/cpuflags_amd64.go $GOROOT/src/runtime/cpuprof.go $GOROOT/src/runtime/cputicks.go $GOROOT/src/runtime/create_file_nounix.go $GOROOT/src/runtime/debug.go $GOROOT/src/runtime/debugcall.go $GOROOT/src/runtime/debuglog.go $GOROOT/src/runtime/debuglog_off.go $GOROOT/src/runtime/env_posix.go $GOROOT/src/runtime/error.go $GOROOT/src/runtime/exithook.go $GOROOT/src/runtime/extern.go $GOROOT/src/runtime/fastlog2.go $GOROOT/src/runtime/fastlog2table.go $GOROOT/src/runtime/float.go $GOROOT/src/runtime/hash64.go $GOROOT/src/runtime/heapdump.go $GOROOT/src/runtime/histogram.go $GOROOT/src/runtime/iface.go $GOROOT/src/runtime/lfstack.go $GOROOT/src/runtime/lockrank.go $GOROOT/src/runtime/lockrank_off.go $GOROOT/src/runtime/malloc.go $GOROOT/src/runtime/map.go $GOROOT/src/runtime/map_fast32.go $GOROOT/src/runtime/map_fast64.go $GOROOT/src/runtime/map_faststr.go $GOROOT/src/runtime/mbarrier.go $GOROOT/src/runtime/mbitmap.go $GOROOT/src/runtime/mcache.go $GOROOT/src/runtime/mcentral.go $GOROOT/src/runtime/mcheckmark.go $GOROOT/src/runtime/mem.go $GOROOT/src/runtime/metrics.go $GOROOT/src/runtime/mfinal.go $GOROOT/src/runtime/mfixalloc.go $GOROOT/src/runtime/mgc.go $GOROOT/src/runtime/mgclimit.go $GOROOT/src/runtime/mgcmark.go $GOROOT/src/runtime/mgcpacer.go $GOROOT/src/runtime/mgcscavenge.go $GOROOT/src/runtime/mgcstack.go $GOROOT/src/runtime/mgcsweep.go $GOROOT/src/runtime/mgcwork.go $GOROOT/src/runtime/mheap.go $GOROOT/src/runtime/minmax.go $GOROOT/src/runtime/mpagealloc.go $GOROOT/src/runtime/mpagealloc_64bit.go $GOROOT/src/runtime/mpagecache.go $GOROOT/src/runtime/mpallocbits.go $GOROOT/src/runtime/mprof.go $GOROOT/src/runtime/mranges.go $GOROOT/src/runtime/msan0.go $GOROOT/src/runtime/msize.go $GOROOT/src/runtime/mspanset.go $GOROOT/src/runtime/mstats.go $GOROOT/src/runtime/mwbbuf.go $GOROOT/src/runtime/nonwindows_stub.go $GOROOT/src/runtime/os_nonopenbsd.go $GOROOT/src/runtime/pagetrace_off.go $GOROOT/src/runtime/panic.go $GOROOT/src/runtime/pinner.go $GOROOT/src/runtime/plugin.go $GOROOT/src/runtime/preempt.go $GOROOT/src/runtime/preempt_nonwindows.go $GOROOT/src/runtime/print.go $GOROOT/src/runtime/proc.go $GOROOT/src/runtime/profbuf.go $GOROOT/src/runtime/proflabel.go $GOROOT/src/runtime/race0.go $GOROOT/src/runtime/rdebug.go $GOROOT/src/runtime/runtime.go $GOROOT/src/runtime/runtime1.go $GOROOT/src/runtime/runtime2.go $GOROOT/src/runtime/runtime_boring.go $GOROOT/src/runtime/rwmutex.go $GOROOT/src/runtime/security_nonunix.go $GOROOT/src/runtime/select.go $GOROOT/src/runtime/sema.go $GOROOT/src/runtime/sizeclasses.go $GOROOT/src/runtime/slice.go $GOROOT/src/runtime/softfloat64.go $GOROOT/src/runtime/stack.go $GOROOT/src/runtime/stkframe.go $GOROOT/src/runtime/string.go $GOROOT/src/runtime/stubs.go $GOROOT/src/runtime/stubs_amd64.go $GOROOT/src/runtime/stubs_nonlinux.go $GOROOT/src/runtime/symtab.go $GOROOT/src/runtime/symtabinl.go $GOROOT/src/runtime/sys_nonppc64x.go $GOROOT/src/runtime/sys_x86.go $GOROOT/src/runtime/tagptr.go $GOROOT/src/runtime/tagptr_64bit.go $GOROOT/src/runtime/time.go $GOROOT/src/runtime/time_nofake.go $GOROOT/src/runtime/timestub.go $GOROOT/src/runtime/timestub2.go $GOROOT/src/runtime/tls_stub.go $GOROOT/src/runtime/trace.go $GOROOT/src/runtime/traceback.go $GOROOT/src/runtime/type.go $GOROOT/src/runtime/typekind.go $GOROOT/src/runtime/unsafe.go $GOROOT/src/runtime/utf8.go $GOROOT/src/runtime/vdso_in_none.go $GOROOT/src/runtime/write_err.go" "$ASM $GOROOT/src/runtime/asm.s $GOROOT/src/runtime/asm_amd64.s $GOROOT/src/runtime/duff_amd64.s $GOROOT/src/runtime/preempt_amd64.s" "-+" "-compiling-runtime"

run rm -f $BUILDDIR/importcfg $BUILDDIR/asm_GOARCH.h $BUILDDIR/go_asm.h $BUILDDIR/symabis

ENDTIME=`date +%s`

echo Done std in $((ENDTIME-STARTTIME))s
