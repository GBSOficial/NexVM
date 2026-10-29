# NexVM — Your OS. Your Freedom.

Gerenciador de máquinas virtuais open source para Macs Apple Silicon, feito para tornar simples, acessível e gratuito rodar Windows e Linux.

**Site e download: <https://nexvm.gbsoficial.com>** · [Releases](https://github.com/GBSOficial/NexVM/releases)

> **Estado: preview (v0.1.0).** Linux ARM64 está testado (instala, reinicia pelo disco, desliga via ACPI). Windows 11 ARM64 é **experimental**: o instalador oficial conclui e o sistema instalado chega ao primeiro uso; desktop, desligamento e rede ainda não foram verificados. Veja [compatibilidade](docs/compatibility/README.md). Nada é afirmado sem teste real.

## O que existe hoje
- App SwiftUI: biblioteca de VMs, criação (nome, SO, CPU, RAM, disco, ISO opcional), iniciar / desligar / reiniciar / forçar parada, excluir dados com confirmação.
- Tela embutida (QEMU em socket unix privado + cliente RFB próprio) com teclado, mouse, rolagem e tela cheia.
- Motor QEMU aarch64 + HVF com QMP, TPM 2.0 por VM (`swtpm`), escolha de firmware UEFI por VM (padrão / Secure Boot), adaptador de rede por VM (e1000e / VirtIO) e ISO de drivers opcional.
- Pacote `.nexvm` com `config.json` versionado, escrita atômica, discos raw esparsos, checagem estrutural de ISO e trava por VM.
- Apenas logs JSONL locais. Sem telemetria, contas ou servidor proprietário.
- Interface em inglês, português (Brasil) e português (Portugal).

## Planejado
Área de transferência, áudio, resolução dinâmica, snapshots, integração com o convidado, Windows App Mode (só projeto, veja [docs](docs/architecture/windows-app-mode.md)). Nada é prometido sem teste.

## Instalação (versão preview)
1. Baixe o `.dmg` notarizado no [site](https://nexvm.gbsoficial.com) ou em [Releases](https://github.com/GBSOficial/NexVM/releases) e arraste o NexVM para Aplicativos.
2. Instale o QEMU (não vem embutido): `brew install qemu swtpm`.
3. Crie uma VM com a sua ISO. ISOs do Windows vêm da Microsoft ([download](https://www.microsoft.com/software-download/windows11arm64)); é preciso licença válida, e o Windows 11 exige um firmware UEFI com Secure Boot instalado por você ([detalhes](docs/compatibility/windows-11-arm64.md)). O NexVM não redistribui nem contorna nada.

Requisitos: Mac Apple Silicon, macOS 14+ (desenvolvido e testado no macOS 27).

## Compilar do código-fonte
```bash
swift build
swift test
scripts/package-app.sh release   # build/NexVM.app — assinatura ad-hoc, SEM notarização
```
Um build local sem notarização gera avisos do Gatekeeper; compile localmente ou use botão direito → Abrir. Não desative o Gatekeeper no sistema. Mantenedores: veja [docs/releasing.md](docs/releasing.md) para releases assinadas e notarizadas. Caminhos específicos da máquina são configurados por variáveis de ambiente (`NEXVM_QEMU_PREFIX`, `NEXVM_FIRMWARE_DIR`, `NEXVM_TEST_ISO`, veja [CLAUDE.md](CLAUDE.md)).

## Contribuir / Segurança / Licença
[CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · MIT ([LICENSE](LICENSE)); notas de terceiros em [NOTICE](NOTICE). English: [README.md](README.md).
