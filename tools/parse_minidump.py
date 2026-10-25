#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""极简 Windows Minidump 解析器：提取异常记录、模块列表、崩溃线程上下文
不依赖任何第三方库，直接按 MINIDUMP 规范读取。
"""
import struct, sys, os

STREAM_THREAD_LIST = 3
STREAM_MODULE_LIST = 4
STREAM_MEMORY_LIST = 5
STREAM_EXCEPTION    = 6
STREAM_SYSTEM_INFO  = 7
STREAM_MEMORY64_LIST = 9

MODULE_SIZE = 108

def u32(b, o):  return struct.unpack_from('<I', b, o)[0]
def u64(b, o):  return struct.unpack_from('<Q', b, o)[0]

def read_mdstring(b, rva):
    n = u32(b, rva)          # bytes, includes null terminator
    raw = b[rva+4: rva+4+n]
    return raw.decode('utf-16-le', errors='replace').rstrip('\x00')

def main(path):
    with open(path, 'rb') as f:
        b = f.read()
    print('file      :', path)
    print('size      :', len(b))
    sig = b[0:4]
    if sig != b'MDMP':
        print('not a minidump: signature', sig); return 1
    n_streams = u32(b, 8)
    dir_rva   = u32(b, 12)
    ts        = u32(b, 20)
    print('streams   :', n_streams)
    print('timestamp :', ts)

    streams = {}
    for i in range(n_streams):
        o = dir_rva + i * 12
        st = u32(b, o); sz = u32(b, o+4); rva = u32(b, o+8)
        streams.setdefault(st, []).append((sz, rva))

    # --- system info ---
    if STREAM_SYSTEM_INFO in streams:
        sz, rva = streams[STREAM_SYSTEM_INFO][0]
        arch = struct.unpack_from('<H', b, rva)[0]
        ver  = struct.unpack_from('<I', b, rva+8)[0]
        print('arch      :', {0:'x86',9:'x64',5:'arm',12:'arm64'}.get(arch, arch))
        print('build     :', struct.unpack_from('<I', b, rva+12)[0])

    # --- modules ---
    modules = []
    if STREAM_MODULE_LIST in streams:
        sz, rva = streams[STREAM_MODULE_LIST][0]
        n = u32(b, rva)
        for i in range(n):
            mo = rva + 4 + i * MODULE_SIZE
            base = u64(b, mo)
            size = u32(b, mo + 8)
            name_rva = u32(b, mo + 20)   # MINIDUMP_MODULE::ModuleNameRva (offset 20, not 32)
            try:
                name = read_mdstring(b, name_rva)
            except Exception:
                name = '?'
            modules.append((base, size, name))
        print('modules   :', len(modules))

    def resolve(addr):
        for base, size, name in modules:
            if base <= addr < base + size:
                return name, addr - base
        return None, None

    # --- exception ---
    if STREAM_EXCEPTION in streams:
        sz, rva = streams[STREAM_EXCEPTION][0]
        tid = u32(b, rva)
        code = u32(b, rva + 8)
        flags = u32(b, rva + 12)
        addr = u64(b, rva + 24)
        nparams = u32(b, rva + 32)
        params = [u64(b, rva + 40 + 8*i) for i in range(min(nparams, 15))]
        print()
        print('--- EXCEPTION ---')
        print('thread id : 0x%x' % tid)
        print('code      : 0x%08x' % code)
        print('flags     : 0x%x' % flags)
        print('address   : 0x%016x' % addr)
        name, off = resolve(addr)
        if name:
            print('module    : %s + 0x%x' % (name, off))
        else:
            print('module    : <not in any module> (wild pointer?)')
        print('params    :', ' '.join('0x%x' % p for p in params))
        # common codes
        known = {
            0xC0000005: 'EXCEPTION_ACCESS_VIOLATION (非法内存访问)',
            0xC000001D: 'EXCEPTION_ILLEGAL_INSTRUCTION',
            0xC0000094: 'EXCEPTION_INT_DIVIDE_BY_ZERO',
            0xC00000FD: 'EXCEPTION_STACK_OVERFLOW',
            0xE06D7363: 'C++ exception (MSVC throw)',
            0x80000003: 'EXCEPTION_BREAKPOINT',
            0xC0000409: 'STATUS_STACK_BUFFER_OVERRUN (__fastfail)',
            0xC0000602: 'STATUS_FAIL_FAST_EXCEPTION',
            0xC0000374: 'STATUS_HEAP_CORRUPTION',
        }
        print('meaning   :', known.get(code, '未知/未列出'))
        # access violation: params[0] rw, params[1] address
        if code == 0xC0000005 and len(params) >= 2:
            rw = params[0]
            tgt = params[1]
            print('access    : %s at 0x%x' % ({0:'read', 1:'write', 8:'execute'}.get(rw, str(rw)), tgt))
            nm2, off2 = resolve(tgt)
            if nm2:
                print('target in : %s + 0x%x' % (nm2, off2))

        # layout: ThreadId u32, align u32(4), MINIDUMP_EXCEPTION (152 bytes), ThreadContext Location
        exc_rel = 8
        exc_size = 4 + 4 + 8 + 8 + 4 + 4 + 8 * 15   # 152
        ctx_size = u32(b, rva + exc_rel + exc_size)
        ctx_rva2 = u32(b, rva + exc_rel + exc_size + 4)
        print('context   : size=%d rva=0x%x' % (ctx_size, ctx_rva2))
        if ctx_size >= 0x100 and ctx_rva2:
            rip = u64(b, ctx_rva2 + 0xF8)
            rsp = u64(b, ctx_rva2 + 0x98)
            rbp = u64(b, ctx_rva2 + 0xA0)
            print('rip       : 0x%016x' % rip)
            nm3, off3 = resolve(rip)
            print('rip module: %s' % (('%s + 0x%x' % (nm3, off3)) if nm3 else '<unknown>'))
            print('rsp       : 0x%016x   rbp: 0x%016x' % (rsp, rbp))
            # scan stack region if present (MemoryList or Memory64List)
            stack = None
            if STREAM_MEMORY64_LIST in streams:
                szl, rval = streams[STREAM_MEMORY64_LIST][0]
                n_ranges = u64(b, rval)
                base_rva = u64(b, rval + 8)
                ranges = []
                for i in range(n_ranges):
                    o = rval + 16 + i * 16
                    start = u64(b, o); dsize = u64(b, o + 8)
                    ranges.append((start, dsize, base_rva))
                    base_rva += dsize
                for start, dsize, rva0 in ranges:
                    if start <= rsp < start + dsize:
                        stack = (start, b[rva0: rva0 + dsize]); break
            elif STREAM_MEMORY_LIST in streams:
                szl, rval = streams[STREAM_MEMORY_LIST][0]
                n_ranges = u32(b, rval)
                for i in range(n_ranges):
                    o = rval + 4 + i * 16
                    start = u64(b, o); dsize = u32(b, o + 8); rva0 = u32(b, o + 12)
                    if start <= rsp < start + dsize:
                        stack = (start, b[rva0: rva0 + dsize]); break
            if stack:
                start, data = stack
                print()
                print('--- STACK SCAN (faulting thread, first 40 qwords from RSP) ---')
                off = rsp - start
                for i in range(40):
                    p = off + 8 * i
                    if p + 8 > len(data): break
                    v = u64(data, p)
                    m, o2 = resolve(v)
                    tag = ('  -> %s + 0x%x' % (m, o2)) if m else ''
                    print('  [rsp+0x%02x] 0x%016x%s' % (8*i, v, tag))
    else:
        print('no exception stream')

    print()
    print('--- module list (top 25 by size) ---')
    for base, size, name in sorted(modules, key=lambda x: -x[1])[:25]:
        print('  0x%016x  %10d  %s' % (base, size, name))
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
