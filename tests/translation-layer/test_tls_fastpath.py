#!/usr/bin/env python3
"""Compile the real loader TLS fast-path with isolated per-thread lifetime tests."""
import ctypes
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOADER = ROOT / "src/translation-layer-next/husk-tl-ld.c"

class FastTLS(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = LOADER.read_text()
        begin = src.index("#define MAX_TLS_MODULES 16")
        end = src.index("/* arg is the descriptor's second word:", begin)
        body = src[begin:end]
        cls.assertTrue(isinstance(body, str))
        assert "_Thread_local tls_thread *tls_current" in body
        assert "pthread_setspecific(g_tls_key, t)" in body
        assert body.index("tls_thread *t = tls_current;") < body.index("pthread_once(&g_tls_once")
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        folder = Path(cls.tmp.name)
        harness = r'''
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
typedef struct { uint64_t base_vaddr; } tl_lib;
static unsigned char tls_template[16] = {7, 3, 1};
static void *waddr(const tl_lib *lib, uint64_t offset) {
    (void)lib;
    if(offset >= sizeof(tls_template)) abort();
    return tls_template + offset;
}
''' + body + r'''
static tl_lib owner;
static pthread_barrier_t bar;
static int errors;
static void *worker(void *argument) {
    uint8_t *p = tl_ld_tls_get_addr(1, 0);
    if(!p || p[0] != 7 || p[1] != 3 || tl_ld_tls_get_addr(1, 0) != p) return (void *)1;
    p[0] = (uint8_t)(uintptr_t)argument;
    pthread_barrier_wait(&bar);
    if(p[0] != (uint8_t)(uintptr_t)argument) errors++;
    return NULL;
}
int run_fast_tls_tests(void) {
    g_ntls = 1;
    g_tlsmod[1].lib = &owner;
    g_tlsmod[1].memsz = 16;
    g_tlsmod[1].filesz = 3;
    g_tlsmod[1].align = 16;
    uint8_t *main_p = tl_ld_tls_get_addr(1, 0);
    if(!main_p || main_p[0] != 7 || main_p[1] != 3) return 1;
    if(tl_ld_tls_get_addr(1, 1) != main_p + 1) return 2;
    if(tl_ld_tls_get_addr(0, 0) || tl_ld_tls_get_addr(17, 0)) return 3;
    main_p[0] = 99;
    pthread_t a,b;
    if(pthread_barrier_init(&bar, NULL, 3)) return 4;
    if(pthread_create(&a,NULL,worker,(void *)(uintptr_t)13)) return 5;
    if(pthread_create(&b,NULL,worker,(void *)(uintptr_t)19)) return 6;
    pthread_barrier_wait(&bar);
    void *ar=NULL,*br=NULL;
    pthread_join(a,&ar);pthread_join(b,&br);
    pthread_barrier_destroy(&bar);
    if(ar || br || errors || main_p[0] != 99) return 7;
    return 0;
}
'''
        (folder / "test.c").write_text(harness)
        subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                        "-shared", "-fPIC", "-pthread", str(folder / "test.c"), "-o", str(folder / "test.so")],
                       check=True)
        cls.lib = ctypes.CDLL(str(folder / "test.so"))

    def test_first_use_template_same_thread_reuse_and_thread_isolation(self):
        self.assertEqual(self.lib.run_fast_tls_tests(), 0)

    def test_real_loader_keeps_pthread_key_destructor_for_thread_exit(self):
        src = LOADER.read_text()
        self.assertIn("pthread_key_create(&g_tls_key, tls_thread_free)", src)
        self.assertIn("pthread_setspecific(g_tls_key, t)", src)
        self.assertIn("tls_current = NULL;", src)

if __name__ == "__main__":
    unittest.main()
