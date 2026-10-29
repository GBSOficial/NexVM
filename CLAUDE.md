# NexVM — guia para Claude Code

## Visão
App open source e gratuito para macOS (Apple Silicon) que gerencia VMs Windows 11 ARM64 e Linux ARM64 com **QEMU + HVF**. Sem telemetria, contas, paywall ou servidor proprietário. Funciona offline. Parallels é só referência de UX, nunca de código/identidade.

## Estado (atualize ao fim de cada fase)
Fase 1 concluída; Fase 2 em andamento: `QEMUEngine` + `QMPClient` validados com QEMU real (firmware UEFI sobe sob HVF; 42 testes passam). Alpine Linux ARM64 (live ISO) chega ao `login:` via serial sob HVF (experimental); app inicia/para a VM com janela QEMU (display virtio-gpu ok); teclado chega mas com teclas perdidas em teste sintético, mouse e instalação em disco não verificados; Windows nunca tentado. ISOs ficam em `/path/to/tools/isos`. QEMU 11.1.3 vive no SSD: `/path/to/tools/homebrew` (tudo de ferramentas/ISOs/caches vai para o SSD, nunca para o disco interno). Não afirme suporte sem teste real (ver `docs/compatibility/`).

## Layout (SwiftPM único na raiz — ver ADR-0001)
- `Sources/NexVMCore` modelos (`VMConfiguration`), validação, `HostResources`, `ResourcePolicy`
- `Sources/NexVMStorage` bundle `.nexvm`, `VMLibrary`, `VMLock`, `PathValidator`, discos, ISO
- `Sources/NexVMEngine` protocolo `VirtualMachineEngine` + `VMRuntimeState` (abstração de backend)
- `Sources/NexVMQEMU` `QEMUCommandBuilder`, `QMP`, `ManagedProcess`, `QEMUBinaryLocator`
- `Sources/NexVMDiagnostics` logger JSONL local
- `Sources/NexVMApp` SwiftUI; strings em `Resources/{en,pt-BR,pt-PT}.lproj`
- Dependências: Core ← Storage/Engine ← QEMU ← App. Não criar ciclos nem módulos vazios (Networking, Display, GuestIntegration, Updater só quando houver código real).

## Comandos
```
swift build                      # debug
swift test                       # todos os testes
scripts/package-app.sh [debug|release]   # gera build/NexVM.app (ad-hoc, sem notarização)
```

## Regras de código
- Swift 6 (strict concurrency). Tipos de domínio `Sendable`. Sem `@unchecked Sendable` sem justificativa em comentário.
- QEMU sempre via `Process` com **argv estruturado**; nunca `sh -c` nem interpolação em shell. Vírgulas em valores de opções QEMU são escapadas (`QEMUOption.escape`).
- Caminhos vindos de config/usuário passam por `PathValidator.resolve`. Diretório do bundle = UUID, nunca o nome da VM.
- Escritas de config: `.atomic`. Bloqueio de VM: `VMLock`. Apagar dados exige `DeletionConfirmation` por VM.
- Sinais só ao pid que o NexVM lançou (`ManagedProcess`); nunca `pkill qemu`.
- Texto de UI só via `L("chave")` + as 3 `.strings`. Nada hardcoded em views.
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
- TPM 2.0 para Windows 11 requer `swtpm` (não incluído no QEMU do Homebrew; a verificar). Sem TPM, o instalador do Windows 11 pode recusar — não implementar bypass.
- Drivers: Windows não tem driver virtio inbox → disco NVMe e NIC e1000e (a validar em boot real).
- Display atual do plano: `-display cocoa` do QEMU (janela separada); display embutido é fase futura.
- Windows App Mode e guest agent: apenas projeto (`docs/architecture/windows-app-mode.md`).
