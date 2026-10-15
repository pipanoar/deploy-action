# pipanoar/deploy-action

GitHub Action oficial do [Pipa no Ar](https://pipanoar.scuderiatech.com.br) para publicar updates OTA de React Native e Expo a partir do CI.

A action valida os inputs, instala o Node e as dependências do projeto e roda `npx hot-updater deploy` para iOS, Android ou os dois. No fim, escreve um resumo no job com plataforma, canal e rollout.

Built on [hot-updater](https://github.com/gronxb/hot-updater). Usa a CLI oficial do hot-updater (1.0.6), sem fork.

## Antes de usar

1. O projeto já publica pelo terminal com `npx hot-updater deploy`. Se ainda não, rode `npx @pipanoar/init` ou siga o [guia rápido](https://docs.pipanoar.scuderiatech.com.br/guia/comecando).
2. O `hot-updater.config.ts` usa o preset [`@pipanoar/hot-updater`](https://docs.pipanoar.scuderiatech.com.br/referencia/pacote). Sem ele, a CLI não sabe publicar no Pipa no Ar.
3. `hot-updater` e `@pipanoar/hot-updater` estão nas `devDependencies`. A action usa a versão do seu lockfile e não baixa outra.
4. No painel, na organização, em **Tokens de deploy**, crie um token com escopo **Deploy**, limitado ao app. Salve como segredo do repositório com o nome `PIPANOAR_TOKEN`.

## Uso básico

Publica iOS e Android no canal `production` a cada push na `main`:

```yaml
# .github/workflows/ota.yml
name: Update OTA

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pipanoar/deploy-action@v1
        with:
          token: ${{ secrets.PIPANOAR_TOKEN }}
```

## Exemplos

### Rollout de 10% na main

Comece baixo e aumente pelo painel depois de olhar os crashes em **Insights**. Rollout abaixo de 100% exige plano Starter ou maior.

```yaml
      - uses: pipanoar/deploy-action@v1
        with:
          token: ${{ secrets.PIPANOAR_TOKEN }}
          rollout: 10
```

### Canal beta nos pull requests

```yaml
on:
  pull_request:

jobs:
  beta:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pipanoar/deploy-action@v1
        with:
          token: ${{ secrets.PIPANOAR_TOKEN }}
          channel: beta
          message: "PR #${{ github.event.pull_request.number }}: ${{ github.event.pull_request.title }}"
```

Nos pull requests o checkout é um commit de merge, por isso vale passar `message`. Pull requests de forks não recebem segredos, então o deploy só funciona para branches do próprio repositório.

### Monorepo

Aponte `working-directory` para a pasta do app (onde fica o `hot-updater.config.ts`). A action sobe a partir dela até a raiz do repositório procurando o lockfile e instala as dependências lá.

```yaml
      - uses: pipanoar/deploy-action@v1
        with:
          token: ${{ secrets.PIPANOAR_TOKEN }}
          working-directory: apps/mobile
```

### Expo

Com Expo (prebuild e o plugin `@hot-updater/expo` com `build: expo()` no config), o uso é o mesmo. Veja o [guia do Expo](https://docs.pipanoar.scuderiatech.com.br/guia/expo).

```yaml
      - uses: pipanoar/deploy-action@v1
        with:
          token: ${{ secrets.PIPANOAR_TOKEN }}
          platform: both
          target-app-version: 1.4.x
```

### Só uma plataforma, com Node e dependências por sua conta

```yaml
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - uses: pipanoar/deploy-action@v1
        with:
          token: ${{ secrets.PIPANOAR_TOKEN }}
          platform: android
          setup-node: false
          install-command: skip
```

## Inputs

| Input | Padrão | O que faz |
|---|---|---|
| `token` | obrigatório | Token de deploy. Vai para a CLI como `PIPANOAR_TOKEN`. |
| `platform` | `both` | `ios`, `android` ou `both` (iOS e depois Android). |
| `channel` | `production` | Canal da release. |
| `rollout` | `100` | Porcentagem de aparelhos, de 0 a 100. |
| `target-app-version` | vazio | Faixa de versões do app, como `1.4.x` (estratégia `appVersion`). |
| `message` | último commit | Mensagem da release. |
| `force-update` | `false` | `true` faz o app recarregar assim que baixar. |
| `disabled` | `false` | `true` cria a release desativada. |
| `working-directory` | `.` | Pasta do app, relativa à raiz do repositório. |
| `setup-node` | `true` | Instala o Node com `actions/setup-node`. |
| `node-version` | `22` | Versão do Node, usada só com `setup-node: true`. |
| `install-command` | detectado | Comando de instalação. Vazio detecta pelo lockfile; `skip` não instala nada. |

A detecção pelo lockfile usa, nesta ordem: `bun.lock` ou `bun.lockb` (`bun install --frozen-lockfile`, com o Bun instalado pela action se faltar), `pnpm-lock.yaml` (`pnpm install --frozen-lockfile`), `yarn.lock` (`yarn install --immutable` no Yarn 2 ou mais novo, `--frozen-lockfile` no Yarn 1) e `package-lock.json` (`npm ci`). pnpm e Yarn vêm do Corepack quando não estão no PATH ou quando o `packageManager` do `package.json` fixa a versão.

Com `platform: both`, o Android só é publicado se o iOS der certo. O resumo do job mostra o que foi publicado, o que falhou e o que não rodou.

## O que é validado

Antes de instalar qualquer coisa, a action confere os inputs e mostra todos os erros de uma vez: token vazio, plataforma fora de `ios`, `android` e `both`, rollout que não é inteiro de 0 a 100, canal com espaço, booleanos diferentes de `true` e `false`, `working-directory` inexistente ou sem `hot-updater.config.*`. Também avisa quando o config não usa o preset do Pipa no Ar e quando o rollout é 0.

## Segurança

- Guarde o token em um segredo (`secrets.PIPANOAR_TOKEN`). Nunca escreva o valor no workflow.
- Use um token de deploy só para o CI, limitado ao app. Se vazar, revogue só ele no painel.
- A action mascara o token no log (`::add-mask::`) e só o entrega ao step do deploy, como `PIPANOAR_TOKEN`. O step de instalação das dependências não recebe o token.
- Fixe a action numa versão (`@v1`) ou, para mais controle, no SHA de um commit.

## Testes

```sh
bash test/run.sh
```

Os testes rodam os scripts de `scripts/` com um `npx` falso no PATH e conferem a validação, os argumentos passados à CLI e o resumo do job.

## English

Official GitHub Action for [Pipa no Ar](https://pipanoar.scuderiatech.com.br), an OTA update service for React Native and Expo built on hot-updater. It validates the inputs, sets up Node, installs dependencies (detected from the lockfile) and runs `npx hot-updater deploy` for iOS, Android or both, then writes a job summary.

```yaml
- uses: actions/checkout@v4
- uses: pipanoar/deploy-action@v1
  with:
    token: ${{ secrets.PIPANOAR_TOKEN }}
    channel: production
    rollout: 10
```

Requirements: `hot-updater` and `@pipanoar/hot-updater` in your devDependencies, and a `hot-updater.config.ts` that uses the `pipanoar()` preset. Store a deploy token scoped to the app as a repository secret. See the inputs table above; messages and docs are in Brazilian Portuguese.

## Licença

MIT. Copyright (c) 2026 ScuderiaTech.
