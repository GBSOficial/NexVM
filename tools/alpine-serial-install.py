#!/usr/bin/env python3
"""Dev tool: drive an Alpine install over QEMU serial on a NexVM bundle (no GUI typing needed).
Mirrors the Linux-guest arguments of QEMUCommandBuilder. Paths assume the SSD layout in CLAUDE.md.
Usage: [NOISO=1] [CHECK=1] tools/alpine-serial-install.py <bundle.nexvm> [shell commands...]
Commands must end by echoing INSTALL-$((1+1))-DONE (the script waits for the evaluated marker)."""
import os, subprocess, sys, time, select, re

B = "/path/to/tools"
BUNDLE = sys.argv[1]
ISO = f"{B}/isos/alpine-virt-3.24.3-aarch64.iso"
Q = f"{B}/homebrew"
args = [f"{Q}/bin/qemu-system-aarch64", "-name", "nexvm-serial", "-nodefaults", "-no-user-config",
  "-machine", "virt", "-accel", "hvf", "-cpu", "host", "-smp", "2", "-m", "2048M",
  "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={Q}/share/qemu/edk2-aarch64-code.fd",
  "-drive", f"if=pflash,format=raw,unit=1,file={BUNDLE}/metadata/vars.fd",
  "-device", "virtio-gpu-pci", "-device", "qemu-xhci", "-device", "usb-kbd", "-device", "usb-tablet",
  "-drive", f"if=none,id=disk0,format=raw,file={BUNDLE}/disks/main.img", "-device", "virtio-blk-pci,drive=disk0,bootindex=1",
  *([] if os.environ.get("NOISO") else ["-drive", f"if=none,id=cd0,media=cdrom,readonly=on,file={ISO}", "-device", "usb-storage,drive=cd0,bootindex=0"]),
  "-netdev", "user,id=net0", "-device", "virtio-net-pci,netdev=net0",
  "-chardev", "stdio,id=s0,signal=off", "-serial", "chardev:s0", "-display", "none", "-monitor", "none"]
p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
buf = b""
log = open(f"{B}/tmp/serial_install.log", "wb")

def read_until(pat, timeout):
    global buf
    end = time.time() + timeout
    rx = re.compile(pat.encode())
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.5)
        if r:
            d = os.read(p.stdout.fileno(), 65536)
            if not d: break
            log.write(d); log.flush(); buf += d
            m = rx.search(buf)
            if m:
                out = buf[:m.end()]; buf = buf[m.end():]
                return out.decode(errors="replace")
    raise TimeoutError(f"timeout waiting for {pat!r}; tail: {buf[-300:]!r}")

def send(s): p.stdin.write(s.encode()); p.stdin.flush()

try:
    out = read_until(r"login: ", 120); print("reached login")
    if os.environ.get("NOISO"):
        print("BANNER:", re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", out)[-160:].replace("\r","").replace("\n","|"))
        if not os.environ.get("CHECK"): raise SystemExit(0)
    send("root\n")
    out = read_until(r"(# |Password: )", 15)
    if out.endswith("Password: "):
        send("\n"); out = read_until(r"(# |Password: |login: )", 15)
    print("login result:", out[-40:].replace("\n", "\\n"))
    if not out.rstrip().endswith("#"): raise SystemExit("could not log in on serial")
    if os.environ.get("CHECK"):
        send("cat /root/nexvm-marker; uname -r; hostname; echo CHECK-$((1+1))-END\n")
        print(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", read_until(r"CHECK-2-END\r?\n", 30))[-200:])
        raise SystemExit(0)
    cmds = sys.argv[2:]
    for c in cmds:
        send(c + "\n")
    read_until(r"INSTALL-2-DONE\r?\n", 120)
    print("install script finished")
finally:
    time.sleep(1)
    p.terminate()
    try: p.wait(10)
    except Exception: p.kill()
