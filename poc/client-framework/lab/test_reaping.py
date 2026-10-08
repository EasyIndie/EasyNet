"""Controlled native API faults only; root executes after independent source review."""
import importlib.util
from pathlib import Path
import signal
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class Stream:
    def __init__(self, fd, world):
        self.fd, self.world, self.closed = fd, world, False

    def fileno(self):
        return self.fd

    def close(self):
        self.closed = True
        self.world.events.append(("close", self.fd))
        if self.world.mode == "close-error" and self.fd == 10:
            raise OSError(5, "fake close failure")


class Process:
    def __init__(self, pid, world):
        self.pid, self.world, self.returncode = pid, world, None
        fd = 10 if pid == 1001 else world.next_fd
        world.next_fd += 2
        self.stdout, self.stderr = Stream(fd, world), Stream(fd + 1, world)

    def wait(self, timeout):
        assert timeout >= 0
        self.world.events.append(("wait", self.pid))
        self.world.waited.add(self.pid)
        if self.world.mode == "wait-timeout" and self.pid == 1001:
            raise subprocess.TimeoutExpired("fake", timeout)
        if self.world.mode == "wait-eintr" and self.pid == 1001:
            raise InterruptedError(4, "fake EINTR")
        if self.world.mode == "helper-reap" and self.pid != 1001:
            raise subprocess.TimeoutExpired("fake helper", timeout)
        self.returncode = 0
        return 0


class Selector:
    def __init__(self, world):
        self.world, self.keys, self.closed = world, {}, False

    def register(self, stream, events, name):
        self.keys[stream.fd] = SimpleNamespace(fileobj=stream, data=name)

    def unregister(self, stream):
        self.keys.pop(stream.fd)

    def select(self, timeout):
        self.world.now += max(0.001, timeout)
        return [(key, 1) for key in list(self.keys.values())]

    def close(self):
        self.closed = True


class World:
    def __init__(self, mode="sole", signal_errors=()):
        self.mode, self.signal_errors = mode, signal_errors
        self.now, self.next_fd = 0, 20
        self.events, self.processes, self.selectors = [], [], []
        self.waited, self.delivered, self.killed = set(), set(), False

    def clock(self):
        self.now += 0.001
        return self.now

    def popen(self, argv, **kwargs):
        if self.processes:
            assert argv == ["/bin/ps", "-g", "1001", "-o", "pid=,ppid=,pgid=,state="]
            pid = 1002 + len(self.processes)
        else:
            assert argv == ["owned-fixed-fake"]
            pid = 1001
        process = Process(pid, self)
        self.processes.append(process)
        return process

    def selector(self):
        result = Selector(self)
        self.selectors.append(result)
        return result

    def waitid(self, which, pid, flags):
        assert pid not in self.waited, "post-Wait observation of recycled PID"
        self.events.append(("observe", pid))
        if pid == 1001 and self.mode == "timeout" and not self.killed:
            return None
        if pid != 1001 and self.mode == "helper-timeout":
            return None
        return SimpleNamespace(si_pid=pid)

    def killpg(self, pid, sig):
        assert pid == 1001 and pid not in self.waited, "unowned/recycled group signal"
        assert sig in (signal.SIGTERM, signal.SIGKILL), "zero-signal absence probe"
        self.events.append(("group", sig))
        if sig in self.signal_errors:
            raise PermissionError(1, "fake signal denial")
        if sig == signal.SIGKILL:
            self.killed = True

    def kill(self, pid, sig):
        assert pid != 1001 and pid not in self.waited
        assert pid in {process.pid for process in self.processes}
        self.events.append(("helper-signal", pid, sig))

    def read(self, fd, size):
        if self.mode == "drain-error" and fd == 10:
            raise OSError(5, "fake drain failure")
        if fd in self.delivered:
            return b""
        self.delivered.add(fd)
        if fd < 20:
            return b"x" * 9000 if self.mode == "overflow" and fd == 10 else b""
        if fd % 2:
            return b"denied" if self.mode == "denied" else b""
        row = b"1001 99 1001 Z\n"
        if self.mode in ("live", "signals") and not self.killed:
            row += b"1008 1001 1001 S\n"
        if self.mode == "zombie-descendant":
            row += b"1008 1001 1001 Z\n"
        if self.mode == "malformed":
            row = b"not metadata\n"
        if self.mode == "malformed-z":
            row = b"1001 99 1001 Zbogus\n"
        if self.mode == "wrong-parent":
            row = b"1001 88 1001 Z\n"
        if self.mode == "truncated":
            row += b" " * 8193
        if self.mode == "row-overflow":
            row += b"".join(f"{2000 + i} 1001 1001 Z\n".encode() for i in range(64))
        return row


class ReapingFaults(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("reaping_subject", Path(__file__).with_name("isolate.py"))
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def execute(self, mode="sole", signal_errors=()):
        world, module = World(mode, signal_errors), self.module
        module._live.clear()
        with patch.object(module.time, "monotonic", world.clock), \
                patch.object(module.subprocess, "Popen", world.popen), \
                patch.object(module.selectors, "DefaultSelector", world.selector), \
                patch.object(module.os, "waitid", world.waitid), \
                patch.object(module.os, "killpg", world.killpg), \
                patch.object(module.os, "kill", world.kill), \
                patch.object(module.os, "read", world.read), \
                patch.object(module.os, "getpid", return_value=99), \
                patch.object(module.os, "set_blocking"):
            result = module._execute(["owned-fixed-fake"], "controlled-fake")
        self.assertEqual(world.events.count(("wait", 1001)), 1)
        wait_index = world.events.index(("wait", 1001))
        self.assertFalse(any(event[0] in ("group", "observe", "helper-signal")
                             for event in world.events[wait_index + 1:]))
        self.assertTrue(all(process.stdout.closed and process.stderr.closed for process in world.processes))
        self.assertTrue(all(selector.closed for selector in world.selectors))
        self.assertLessEqual(result["elapsed_s"], 2.03)
        return result, world

    def test_natural_exit_sole_reserved_zombie(self):
        result, world = self.execute()
        self.assertTrue(result["reaped"])
        self.assertFalse(result["signals"])
        self.assertTrue(result["leader_wait_completed"])
        self.assertTrue(result["stdout_eof"] and result["stderr_eof"])
        self.assertFalse(self.module._live)
        self.assertLess(result["elapsed_s"], 1)

    def test_term_kill_denials_never_skip_wait(self):
        for failures in ((signal.SIGTERM,), (signal.SIGKILL,), (signal.SIGTERM, signal.SIGKILL)):
            with self.subTest(failures=failures):
                result, world = self.execute("signals", failures)
                self.assertFalse(result["reaped"])
                self.assertTrue(result["leader_wait_completed"])
                self.assertEqual([event[1] for event in world.events if event[0] == "group"],
                                 [signal.SIGTERM, signal.SIGKILL])
                denied = [item for item in result["errors"] if item["errno"] == 1]
                self.assertEqual(len(denied), len(failures))
                self.assertEqual(self.module._live, {1001})
                with patch.object(self.module.sys, "platform", "darwin"), \
                        patch.object(self.module.os, "getuid", return_value=501), \
                        patch.object(self.module, "_root", return_value=Path("/owned-fake")):
                    with self.assertRaisesRegex(ValueError, "previous child"):
                        self.module.run_probe("unused", "unused", [])

    def test_membership_unknowns_cannot_use_eof_as_proof(self):
        for mode in ("zombie-descendant", "denied", "malformed", "malformed-z", "wrong-parent", "truncated", "row-overflow"):
            with self.subTest(mode=mode):
                result, _ = self.execute(mode)
                self.assertFalse(result["reaped"])
                self.assertNotEqual(result["group_check"], "sole-zombie")
                self.assertEqual(self.module._live, {1001})

    def test_live_owned_group_may_qualify_only_after_snapshot(self):
        result, _ = self.execute("live")
        self.assertTrue(result["reaped"])
        self.assertEqual(result["group_check"], "sole-zombie")
        self.assertEqual(result["signals"], ["signal-term", "signal-kill"])

    def test_independent_wait_drain_helper_and_close_failures(self):
        for mode in ("wait-timeout", "wait-eintr", "drain-error", "overflow", "helper-timeout", "helper-reap", "close-error"):
            with self.subTest(mode=mode):
                result, _ = self.execute(mode)
                self.assertFalse(result["reaped"])
                self.assertTrue(result["errors"])
                self.assertEqual(self.module._live, {1001})
                if mode == "overflow":
                    self.assertEqual(result["stdout_count"], 9000)
                    self.assertEqual(len(result["stdout"]), 8192)
                if mode.startswith("wait-"):
                    self.assertFalse(result["leader_wait_completed"])

    def test_timeout_is_not_absence_proof(self):
        result, _ = self.execute("timeout")
        self.assertTrue(result["timed_out"])
        self.assertFalse(result["reaped"])
        self.assertTrue(result["leader_wait_completed"])


if __name__ == "__main__":
    unittest.main()
