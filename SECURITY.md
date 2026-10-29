# Security policy
NexVM runs complete operating systems, so security reports are welcome and taken seriously.

**Reporting:** do not open a public issue. Once the repository is published, use GitHub's private vulnerability reporting ("Security" tab → "Report a vulnerability"). The contact channel will be filled in here at publication time.

Please include version/commit, macOS version, steps to reproduce and impact. We aim to acknowledge reports within 7 days and to coordinate a fix and disclosure timeline with you.

In scope: path traversal, command injection into QEMU arguments, unsafe file permissions, unintended network exposure, data loss on delete. Out of scope: vulnerabilities in guest operating systems or in QEMU itself (report upstream).
