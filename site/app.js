// Language switch (pt-BR default in the markup, English dictionary here). No network, no tracking.
(function () {
  var EN = {
    "skip": "Skip to content",
    "nav.features": "Features", "nav.start": "Get started", "nav.status": "Status",
    "hero.eyebrow": "Open source · MIT · Apple Silicon",
    "hero.title": "Windows and Linux on your Mac. <span class=\"grad\">Truly free.</span>",
    "hero.lead": "NexVM is a free, open-source virtual machine manager for Apple Silicon Macs. It uses QEMU with HVF acceleration. No telemetry, no accounts, no proprietary server, works offline.",
    "hero.download": "Download for macOS", "hero.github": "View source on GitHub",
    "badge.chip": "Apple Silicon", "badge.macos": "macOS 14+", "badge.preview": "Preview 0.1", "badge.free": "Free",
    "shot.alt": "NexVM main window listing two virtual machines: Windows 11 ARM64 and Alpine Linux ARM64.",
    "shot.cap": "The NexVM virtual machine library (macOS, dark theme).",
    "feat.title": "Built to be simple, open and safe",
    "f1.t": "Windows 11 ARM64", "f1.d": "Official Microsoft installer with TPM 2.0 (swtpm) and Secure Boot. No shortcuts: NexVM does not bypass requirements or activation.",
    "f2.t": "Linux ARM64", "f2.d": "Installs, reboots from disk and shuts down via ACPI. Tested with Alpine Linux.",
    "f3.t": "Embedded display", "f3.d": "The VM screen appears in its own window, with keyboard, mouse, scrolling and full screen.",
    "f4.t": "Private by default", "f4.d": "No telemetry, no accounts, no public ports. Logs stay on your Mac. The code is open for you to audit.",
    "f5.t": "Native on macOS", "f5.d": "SwiftUI app with light and dark themes, one window per VM, and a UI in English and Portuguese (Brazil and Portugal).",
    "f6.t": "Your data, your control", "f6.d": "Each VM is a <code>.nexvm</code> bundle with its disk and configuration. Deleting data always asks for confirmation.",
    "start.title": "Get started",
    "s1.t": "Download and install NexVM", "s1.d": "Download the <code>.dmg</code> below and drag NexVM to your Applications folder.",
    "s2.t": "Install QEMU", "s2.d": "NexVM does not include QEMU. With Homebrew:", "s2.n": "<code>swtpm</code> is required for Windows 11 (TPM 2.0).",
    "s3.t": "Create your VM with your own ISO", "s3.d": "Download the Windows 11 ARM64 ISO from Microsoft's website (a valid license is required) or an ARM64 Linux distribution, then use the new machine wizard.",
    "s.note": "Windows 11 also needs a UEFI firmware with Secure Boot, which you install yourself. See the <a href=\"https://github.com/GBSOficial/NexVM/blob/main/docs/compatibility/windows-11-arm64.md\" rel=\"noopener\">compatibility notes</a>.",
    "st.title": "Honest status: preview 0.1", "st.lead": "We only call something ready when it was really tested.",
    "st.c1": "Item", "st.c2": "State",
    "st.ok": "Tested: installs, reboots and shuts down",
    "st.exp": "Experimental: the installer completes and the installed system reaches first-run setup. Desktop, shutdown and network are not verified yet",
    "st.r3": "Clipboard, audio, resizable display", "st.plan": "Planned",
    "st.note": "Follow the tests in <a href=\"https://github.com/GBSOficial/NexVM/tree/main/docs/compatibility\" rel=\"noopener\">docs/compatibility</a>.",
    "dl.title": "Download NexVM",
    "dl.lead": "Preview build, signed with a Developer ID and notarized by Apple. For Apple Silicon Macs on macOS 14 or later.",
    "dl.btn": "Download the latest version (.dmg)",
    "dl.note": "The file lives in GitHub Releases, next to its SHA-256 checksum. Prefer to build it yourself? See the <a href=\"https://github.com/GBSOficial/NexVM#build\" rel=\"noopener\">build guide</a>.",
    "q1": "Is it really free?", "a1": "Yes. NexVM is open source under the MIT license. There is no paid version, subscription or account.",
    "q2": "Do I need a Windows license?", "a2": "Yes. You download the ISO from Microsoft and use your own license. NexVM does not distribute Windows, provide keys, or bypass activation or system requirements.",
    "q3": "Does NexVM collect any data?", "a3": "No. There is no telemetry and no network service of its own. Logs stay only on your Mac.",
    "q4": "Does it work on Intel Macs?", "a4": "No. The focus is Apple Silicon, running ARM64 systems with Apple's hypervisor acceleration.",
    "q5": "Is it affiliated with Microsoft, Apple or QEMU?", "a5": "No. Windows is a Microsoft trademark, macOS and Apple Silicon are Apple trademarks, and QEMU is an independent project. NexVM is an independent project that uses QEMU.",
    "foot.by": "by", "foot.sec": "Security", "foot.lic": "License"
  };
  var nodes = Array.prototype.slice.call(document.querySelectorAll("[data-i18n]"));
  var alts = Array.prototype.slice.call(document.querySelectorAll("[data-i18n-alt]"));
  var pt = {}, ptAlt = {};
  nodes.forEach(function (n) { pt[n.getAttribute("data-i18n")] = n.innerHTML; });
  alts.forEach(function (n) { ptAlt[n.getAttribute("data-i18n-alt")] = n.getAttribute("alt"); });
  var btn = document.getElementById("lang");

  function apply(lang) {
    var en = lang === "en";
    nodes.forEach(function (n) {
      var k = n.getAttribute("data-i18n");
      n.innerHTML = en && EN[k] ? EN[k] : pt[k];
    });
    alts.forEach(function (n) {
      var k = n.getAttribute("data-i18n-alt");
      n.setAttribute("alt", en && EN[k] ? EN[k] : ptAlt[k]);
    });
    document.documentElement.lang = en ? "en" : "pt-BR";
    btn.textContent = en ? "PT" : "EN";
    try { localStorage.setItem("nexvm-lang", lang); } catch (e) { /* storage may be blocked */ }
  }

  var saved = null;
  try { saved = localStorage.getItem("nexvm-lang"); } catch (e) { /* ignore */ }
  var start = saved || ((navigator.language || "pt").toLowerCase().indexOf("pt") === 0 ? "pt" : "en");
  if (start === "en") apply("en");
  btn.addEventListener("click", function () { apply(document.documentElement.lang === "en" ? "pt" : "en"); });
})();
