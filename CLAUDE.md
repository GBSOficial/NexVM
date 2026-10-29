# NexVM — guia para Claude Code

## Visão
App open source e gratuito para macOS (Apple Silicon) que gerencia VMs Windows 11 ARM64 e Linux ARM64 com **QEMU + HVF**. Sem telemetria, contas, paywall ou servidor proprietário. Funciona offline. Parallels é só referência de UX, nunca de código/identidade.

## Estado (atualize ao fim de cada fase)
Fase 1 concluída; Fase 2 em andamento: `QEMUEngine` + `QMPClient` validados com QEMU real (firmware UEFI sobe sob HVF; 42 testes passam). Alpine Linux ARM64: live ISO boota, instala no disco do bundle, reinicia pelo disco com dados mantidos e desliga via ACPI (testado; ver docs/compatibility). Mouse não verificado (console texto); sem desktop gráfico testado; Windows 11: instalador completa e o sistema instalado boota até o primeiro uso (OOBE) com edk2 2024.02 Secure Boot (não embutido; builds Debian 2025.02/Fedora 2026 travam no HVF); desktop, desligamento e rede não verificados. QEMU 11.1.3 fica em um prefixo Homebrew separado, localizado por `NEXVM_QEMU_PREFIX`; ISOs e firmware são do usuário e nunca vão para o Git. Não afirme suporte sem teste real (ver `docs/compatibility/`).

## Layout (SwiftPM único na raiz — ver ADR-0001)
- `Sources/NexVMCore` modelos (`VMConfiguration`), validação, `HostResources`, `ResourcePolicy`
- `Sources/NexVMStorage` bundle `.nexvm`, `VMLibrary`, `VMLock`, `PathValidator`, discos, ISO
- `Sources/NexVMEngine` protocolo `VirtualMachineEngine` + `VMRuntimeState` (abstração de backend)
- `Sources/NexVMQEMU` `QEMUCommandBuilder`, `QMP`, `ManagedProcess`, `QEMUBinaryLocator`
- `Sources/NexVMDiagnostics` logger JSONL local
- `Sources/NexVMDisplay` cliente RFB 3.8 (socket unix), `MacKeyMap` (mac keycode → scancode XT)
- `Sources/NexVMApp` SwiftUI. `Design/` (tema NexVMTheme, componentes), `Views/` (MainWindow, VMCard, NewVMWizard, VMWindow, DiagnosticsView, SettingsView), `Support/` (L() i18n, HardwareDefaults), `LibraryViewModel` (estado de UI na MainActor; ciclo de vida vive no `QEMUEngine`). Strings em `Resources/{en,pt-BR,pt-PT}.lproj`; assets em `Resources/Assets.xcassets`; marca em `assets/brand/`.
- Janelas: `Window("main")` gerenciamento, `WindowGroup(for: UUID)` uma janela por VM, `Settings` scene. Fechar janelas NÃO para VMs; sair do app com VM rodando pede confirmação e faz force-stop (sem QEMU órfão).
- Dependências: Core ← Storage/Engine ← QEMU ← App. Não criar ciclos nem módulos vazios (Networking, Display, GuestIntegration, Updater só quando houver código real).

## Comandos
```
swift build                      # debug
swift test                       # todos os testes
scripts/package-app.sh [debug|release]   # gera build/NexVM.app (ad-hoc, sem notarização) com AppIcon.icns
python3 scripts/check-strings.py          # toda L("chave") existe nas 3 línguas
xcodebuild -scheme NexVM-Package -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode test
```

## Regras de código
- Swift 6 (strict concurrency). Tipos de domínio `Sendable`. Sem `@unchecked Sendable` sem justificativa em comentário.
- QEMU sempre via `Process` com **argv estruturado**; nunca `sh -c` nem interpolação em shell. Vírgulas em valores de opções QEMU são escapadas (`QEMUOption.escape`).
- Caminhos vindos de config/usuário passam por `PathValidator.resolve`. Diretório do bundle = UUID, nunca o nome da VM.
- Escritas de config: `.atomic`. Bloqueio de VM: `VMLock`. Apagar dados exige `DeletionConfirmation` por VM.
- Sinais só ao pid que o NexVM lançou (`ManagedProcess`); nunca `pkill qemu`.
- Texto de UI só via `L("chave")` + as 3 `.strings` (rode check-strings.py). Nada hardcoded em views. Cores: só `NexVMTheme`; superfícies/texto com cores semânticas do sistema (Light/Dark). Estado nunca só por cor (ícone+texto). Debug: `NEXVM_COLOR_SCHEME=light|dark`, `NEXVM_LIBRARY_PATH=<abs>`, `NEXVM_QEMU_PREFIX=<abs>`, `NEXVM_FIRMWARE_DIR=<abs>`, `NEXVM_TEST_ISO=<abs>`.
- Sem botão/recurso sem implementação real; marcar como planejado/experimental.
- Commits pequenos, Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## Segurança
Menor privilégio, sem sudo, sem kext, sem portas públicas (rede `userNAT` sem hostfwd, QMP só em socket unix), logs 0600, sem segredos no Git, nunca ISO/disco/firmware no Git. ISO da Microsoft é baixada pelo usuário; não redistribuir; não burlar ativação/TPM.

## Regras permanentes
1. Nunca remover arquivos do usuário nem tocar dados de outros apps.
2. Não publicar repositório/release/push remoto sem autorização explícita.
3. Não instalar ferramentas globais (brew etc.) sem avisar e documentar.
4. Rodar `swift test` após mudanças relevantes; não declarar "funciona" sem verificar.
5. Documentar decisões em `docs/decisions/` (ADR). Respeitar licenças (inventário em `NOTICE`).
6. Testes de integração com QEMU real ficam atrás de detecção do binário e são pulados (`XCTSkip`) se ausente.

## Limitações conhecidas
- Virtualization.framework não é backend: Windows guest não é oficialmente suportado por ela (ADR-0002).
- TPM 2.0 para Windows 11: engine gerencia `swtpm` por VM (`SwtpmLaunch`, estado em `metadata/tpm`) e RECUSA iniciar Windows sem ele; `swtpm` 0.10.2 instalado no prefixo do QEMU e validado com QEMU real (TPM no firmware; `tpm-tis-device` exige `ppi=off` sob HVF), e o instalador oficial do Windows 11 ARM64 já roda na tela embutida até a escolha de edição (instalação NÃO concluída; ver docs/compatibility/windows-11-arm64.md). Não implementar bypass de requisitos.
- Drivers: Windows não tem driver virtio inbox → disco NVMe e NIC e1000e (a validar em boot real).
- Display: embutido via VNC em socket unix privado + cliente RFB próprio (`NexVMDisplay`, ADR-0005); fallback `-display cocoa,zoom-to-fit=on` em Ajustes → Avançado. Sem clipboard, áudio, redimensionamento dinâmico; display embutido e tela cheia dentro do NexVM não existem (a janela da VM diz isso). "Restart" = `system_reset` (reset de hardware), não reboot gracioso.
- Ícone/marca: master do ícone é upscale de ~257 px e SVGs são reconstruções aproximadas (ver assets/brand/README.md); refazer em resolução nativa antes de release.
- Windows App Mode e guest agent: apenas projeto (`docs/architecture/windows-app-mode.md`).
