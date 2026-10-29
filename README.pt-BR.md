# NexVM — Your OS. Your Freedom.

Gerenciador de máquinas virtuais open source para Macs Apple Silicon, feito para tornar simples, acessível e gratuito rodar Windows e Linux.

> **Estado: fundação inicial (v0.1.0-dev).** O NexVM cria e gerencia *pacotes* de VM, mas **ainda não inicia nenhuma VM**. Nenhum sistema convidado foi bootado. Veja [compatibilidade](docs/compatibility/README.md).

## O que existe hoje
- App SwiftUI: biblioteca de VMs, criação (nome, SO, CPU, RAM, disco, ISO opcional), remover da biblioteca, excluir dados com confirmação.
- Pacote `.nexvm` com `config.json` versionado, escrita atômica, discos raw esparsos, checagem estrutural de ISO e trava por VM.
- Montador de comando QEMU aarch64/HVF, parser QMP e gestão segura de processo filho (testados em unidade; ainda não rodados com QEMU real).
- Logs JSONL locais. Sem telemetria, contas ou acesso à rede.
- Interface em inglês, português (Brasil) e português (Portugal).

## Planejado
Boot de Linux ARM64, instalação do Windows 11 ARM64, display/entrada, snapshots, integração com o convidado, Windows App Mode (só projeto). Nada é prometido sem teste.

## Requisitos
Mac Apple Silicon, macOS 14+, Xcode com Swift 6. O QEMU é instalado à parte (`brew install qemu`) e não vem embutido. A ISO do Windows vem da Microsoft e exige licença válida; o NexVM não redistribui nem contorna nada.

## Build
```bash
swift build
swift test
scripts/package-app.sh release   # build/NexVM.app — assinatura ad-hoc, SEM notarização
```
App sem notarização gera avisos do Gatekeeper; compile localmente ou use botão direito → Abrir.

Licença MIT. Veja [CONTRIBUTING](CONTRIBUTING.md), [SECURITY](SECURITY.md) e [NOTICE](NOTICE).
