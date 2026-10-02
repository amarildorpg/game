# Caminho do Poder

Jogo de puzzle e estratégia para **Android (modo retrato)**, feito em **Godot 4**. Você anda por um tabuleiro, coleta itens e enfrenta inimigos: toque em uma casa adjacente para andar, e lembre que seu poder precisa ser **estritamente maior** que o do inimigo para vencê-lo.

> ## 🚧 Jogo em desenvolvimento
>
> Este é um **protótipo** (versão `0.1.0`). A jogabilidade, o balanceamento, a arte e os sons ainda estão mudando, e há partes inacabadas.
> **Sugestões, relatos de bugs e ajuda são bem-vindos** — abra uma *issue* ou envie um *pull request*.

## Como se joga

- Você começa com **poder 1** e **3 vidas** em toda tentativa.
- Toque em uma casa adjacente para andar até ela.
- **Inimigo com poder menor** que o seu: você vence, soma o poder dele ao seu e a casa fica livre.
- **Inimigo com poder igual ou maior**: você perde uma vida e não se move.
- **Itens** (poções, armas, armaduras, botas, amuletos etc.) aumentam seu poder ou suas vidas.
- Perdeu as 3 vidas: a fase atual reinicia ao tocar em **REINICIAR**.
- Se a tentativa não tiver mais solução (nenhum inimigo vencível e nenhum item que ajude), o jogo mostra **"ESCOLHA OUTRO CAMINHO"** e oferece reiniciar, sem descontar uma vida injustamente.
- Vencer a fase salva o progresso e volta à tela inicial. O botão **X** pede confirmação (**SAIR** / **VOLTAR**) antes de fechar o jogo.

## Recursos

- 8 fases-base desenhadas à mão e geração procedural até a **fase 999**. Concluir a 999 mostra **"VOCÊ É CAMPEÃO!"** e reinicia o progresso.
- Só a geometria das fases-base é fixa; os itens e o poder dos inimigos são **gerados de novo a cada tentativa**, com dificuldade crescente.
- Um validador garante que toda fase tenha ao menos uma solução sem perder vidas.
- A cada 15 fases o cenário muda de paleta (um "bioma" novo); a cada 50 aparece o aviso `MARCO! FASE X`.
- Efeitos sonoros gerados em código (sem arquivos de áudio externos) e vibração no celular nos principais eventos.
- Progresso salvo localmente (`user://save.json`).

## Como executar

1. Instale o [Godot 4](https://godotengine.org/download) (o projeto foi desenvolvido na série 4.x, renderizador *GL Compatibility*).
2. No gerenciador de projetos, importe o arquivo `project.godot`.
3. Execute com **F5** (ou **F6** para a cena atual). No computador, o clique do mouse emula o toque.

## Testar no Android

**Emulador:** use uma imagem de sistema com GPU do host e inicie o emulador com `-gpu host`. Sem isso o emulador cai na renderização por software (SwiftShader), e o shader de canvas do Godot pode falhar silenciosamente (`Fragment shader active uniforms exceed GL_MAX_FRAGMENT_UNIFORM_VECTORS`), deixando a tela cinza sem nenhum erro óbvio.

```bash
emulator -avd <nome-do-seu-avd> -gpu host -no-boot-anim
adb install -r build/CaminhoDoPoder.apk
adb shell monkey -p com.amarildo.caminhodopoder -c android.intent.category.LAUNCHER 1
```

**Aparelho real:** ative a depuração USB e instale o APK com `adb install -r`.

## Gerar o APK

1. No Godot, configure o Android SDK em **Editor > Editor Settings > Export > Android** (precisa de `build-tools` e de um keystore de debug).
2. Instale os modelos de exportação em **Editor > Manage Export Templates**.
3. Exporte em **Project > Export > Android Debug**, ou pela linha de comando:

```bash
godot --headless --path . --export-debug "Android Debug" build/CaminhoDoPoder.apk
```

A pasta `build/`, os modelos de exportação (`*.tpz`) e os APKs **não** são versionados. Para uma versão de distribuição, use a sua própria chave de assinatura (nunca a coloque no repositório).

## Organização do projeto

| Caminho | Conteúdo |
| --- | --- |
| `project.godot`, `main.tscn` | Configuração do projeto (720×1280, retrato) e cena principal. |
| `scripts/main.gd` | Telas, toque, combate, itens, animações, HUD, áudio, vibração e salvamento. |
| `scripts/level_validator.gd` | Busca todas as rotas e combinações de itens e inimigos; valida que existe solução sem perder vidas e detecta, em tempo real, quando a tentativa atual não tem mais como vencer. |
| `scripts/validate_generated_levels.gd` | Script para validar em lote as fases geradas. |
| `data/levels.json` | As fases-base. |
| `data/config.json` | Poder e vidas iniciais, máximo de vidas e bônus dos itens. |
| `assets/sprites/` | Sprites do herói, dos inimigos e dos equipamentos. |
| `export_presets.cfg` | Preset de exportação Android (debug). |

### Dados das fases e dos itens

- Posição: `[x, y]`, contando a partir de `0` no canto superior esquerdo.
- Tipos de item: `plus1`, `sword`, `helmet`, `crown`, `heart`, `double`, `axe`, `spear`, `hammer`, `shield`, `armor`, `cape`, `boots`, `amulet`, `staff`.
- Da fase 9 até a 999 o jogo gera as fases sozinho, reaproveitando a malha da última fase-base. A fase 999 tem exatamente 100 casas (grade 10×10).

## Como contribuir

1. Faça um fork e crie uma branch para a sua alteração.
2. Abra o projeto no Godot e teste a fase que você mexeu (e, se mudou fases ou regras, rode o validador).
3. Descreva no pull request o que mudou e como testar.

## Licença

Ainda não definida. Enquanto não houver um arquivo `LICENSE`, todos os direitos permanecem com o autor. Os sprites em `assets/sprites/` fazem parte do jogo; se quiser reutilizá-los, abra uma issue para combinarmos.
