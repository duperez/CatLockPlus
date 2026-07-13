<div align="center">

# 🐱🔒 CatLockPlus

**Trava teclado, mouse, trackpad e Touch Bar para o seu gato deitar no MacBook em paz.**

![macOS](https://img.shields.io/badge/macOS-11%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![Licença](https://img.shields.io/badge/licen%C3%A7a-MIT-green)
![PRs](https://img.shields.io/badge/PRs-bem--vindos-brightgreen)

</div>

---

## 🐈 Por que esse app existe?

Meu gato adora deitar em cima do teclado do meu MacBook. Existem apps que travam o teclado, mas nenhum resolvia meu problema por completo: o que eu usava não travava o mouse nem a Touch Bar, então o gato pausava minhas músicas, mudava o brilho e arrastava janelas com a barriga.

Procurei uma solução open source e fácil de usar, e não encontrei. Então fiz a minha, e estou compartilhando para o próximo humano de gato que passar pelo mesmo.

## ✨ O que ele faz

Quando travado, o CatLockPlus bloqueia tudo o que um gato consegue acionar:

| | Bloqueio |
|---|---|
| ⌨️ **Teclado** | Todas as teclas (exceto o atalho de destravar) |
| 🖱️ **Mouse e trackpad** | Cursor congelado: cliques, arrastar, scroll e gestos |
| 🎚️ **Touch Bar** | Teclas de brilho, volume e mídia bloqueadas; overlay "🔒 Travado" cobre a barra* |
| 🐱 **Barra de menu** | Ícone mostra o estado: 🐱 livre / 🔒 travado |

Para **travar**: atalho de teclado (padrão `⌃L`), menu 🐱 → "Travar agora", ou o botão 🔒🐱 na Touch Bar*.
Para **destravar**: o mesmo atalho.

**Atalho configurável:** menu 🐱 → Preferências… → clique no botão e pressione a combinação que quiser. Fica salvo entre reinícios.

<sub>\* O overlay e o botão na Touch Bar usam APIs privadas da Apple e funcionam nos MacBook Pro com Touch Bar (2016 a 2020, incluindo o MacBook Pro 13" M1). No macOS Tahoe (26.x) há uma instabilidade conhecida sendo investigada. O bloqueio das teclas da Touch Bar funciona mesmo assim, pois usa outro mecanismo.</sub>

## 💻 Compatibilidade

Funciona em qualquer Mac com macOS 11 (Big Sur) ou superior, já que a trava de teclado/mouse usa APIs públicas e estáveis do sistema. Em Macs sem Touch Bar tudo funciona igual; você só não vê o botão na barra (porque ela não existe 🙂).

## 📦 Instalação

### Opção 1: baixar a build pronta

1. Baixe o `.zip` da [página de Releases](../../releases) e descompacte
2. Arraste o `CatLockPlus.app` para a pasta **Aplicativos**
3. Siga o passo **"Abrindo pela primeira vez"** abaixo 👇

#### ⚠️ Abrindo pela primeira vez (aviso do macOS)

Este projeto é gratuito e eu preferi não pagar os US$ 99/ano do programa de desenvolvedores da Apple, que seria necessário para assinar e notarizar o app. Por isso, na primeira abertura o macOS mostra um aviso de "desenvolvedor não identificado" ou "não foi possível verificar". O app não está quebrado; é só o macOS sendo cauteloso com apps de fora da App Store. Para abrir:

1. Clique no app com o **botão direito** (ou `Ctrl` + clique) → **Abrir**
2. Na janela de aviso, clique em **Abrir** de novo

Se o botão "Abrir" não aparecer: **Ajustes do Sistema → Privacidade e Segurança**, role até o final e clique em **"Abrir Assim Mesmo"**. Alternativa pelo Terminal:

```bash
xattr -cr /Applications/CatLockPlus.app
```

Isso é necessário uma única vez. Como o projeto é open source, você pode auditar cada linha do que está rodando, ou usar a Opção 2 e compilar você mesmo.

### Opção 2: compilar do código-fonte

Precisa apenas das ferramentas de linha de comando da Apple (`xcode-select --install`):

```bash
git clone https://github.com/duperez/CatLockPlus.git
cd CatLockPlus
bash build.sh
open CatLockPlus.app
```

Compilar localmente também evita o aviso do Gatekeeper.

## 🔐 Permissão de Acessibilidade (primeira execução)

Para conseguir bloquear teclado e mouse, o app intercepta os eventos de entrada do sistema, e o macOS (corretamente!) exige sua autorização para isso:

1. Ao abrir o app pela primeira vez, o macOS vai pedir a permissão
2. Vá em **Ajustes do Sistema → Privacidade e Segurança → Acessibilidade**
3. Ative o **CatLockPlus**

O app detecta a permissão sozinho em ~2 segundos, sem precisar reabrir.

**Privacidade:** o CatLockPlus não registra teclas, não coleta dados e não acessa a internet. Os eventos são apenas bloqueados ou deixados passar; nada é armazenado. Não acredite em mim: [leia o código](main.swift), é um arquivo só.

## 🚨 Se algo der errado

A trava vive dentro do processo do app. Se o app fechar, tudo destrava instantaneamente. Então, no pior dos casos:

- Encerre o app pelo menu 🐱 → Sair (se o mouse estiver livre), ou
- Segure o botão de ligar para desligar o Mac, ou
- Via SSH de outra máquina: `killall CatLockPlus`

Não existe estado em que a trava "sobrevive" ao app. Reiniciar o Mac também resolve sempre.

## ⚙️ Como funciona (para os curiosos)

- **Teclado/mouse/trackpad:** um `CGEventTap` no nível da sessão intercepta os eventos de entrada (`keyDown`, `mouseMoved`, cliques, scroll, gestos e eventos de sistema como brilho/volume) e os descarta enquanto travado, exceto o atalho de destravar.
- **Touch Bar:** usa as APIs privadas do framework `DFRFoundation` (as mesmas de projetos como o [Pock](https://github.com/pock/pock)) para adicionar o botão à Control Strip e cobrir a barra com um overlay durante a trava. Por serem privadas, podem quebrar entre versões do macOS.
- **Atalho:** salvo em `UserDefaults`, comparado por keycode + modificadores direto no event tap.

## ⚠️ Limitações conhecidas

- O botão/overlay da Touch Bar está instável no macOS Tahoe 26.x (issue aberta, ajuda é bem-vinda!)
- Build sem assinatura da Apple gera o aviso do Gatekeeper na primeira abertura (explicado acima)
- O app não impede o gato de *desligar* o Mac segurando o Touch ID/botão de ligar. Isso é hardware 🤷

## 🤝 Contribuindo

Issues e PRs são muito bem-vindos, especialmente de quem tiver um MacBook com Touch Bar no Tahoe para ajudar a depurar o overlay, ou quiser adicionar traduções.

## 📄 Licença

[MIT](LICENSE): use, modifique e distribua à vontade.
