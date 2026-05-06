# Client Pack

Helpers que entram no zip do client gerado pela CI [`build-mumain-client.yml`](../.github/workflows/build-mumain-client.yml).

## Conteúdo

| Arquivo | Vai pro zip como | Pra quê |
|---|---|---|
| `play.bat` | `play.bat` | Launcher Windows que chama `main.exe connect /uSERVER /pPORT` |
| `README.player.txt` | `LEIA-ME.txt` | Instruções pro jogador final (PT-BR) |

## Como rodar a CI

### Caminho A — manual (recomendado pra primeira vez)

1. Vai em **Actions** no GitHub do `gian0205/openmucoolify`.
2. Seleciona **Build MuMain Client** na lateral.
3. **Run workflow** → preenche:
   - `mumain_ref`: deixa `main` ou pinha um commit específico (ex.: `abc1234`)
   - `create_release`: marca se quiser que vire uma GitHub Release
4. Roda. Demora uns 15–25 min na primeira vez (build C++ no Windows runner).
5. Quando terminar, baixa o `mumain-client.zip` da aba **Artifacts** do run.

### Caminho B — por tag (pro lançamento "oficial")

```bash
git tag client-v0.1
git push origin client-v0.1
```

A CI dispara, builda, e cria automaticamente uma **GitHub Release** com o zip anexado.

## O que o player recebe

Estrutura do zip:

```
MuPorcaria-Client-<sha>.zip
├── main.exe              ← MuMain compilado
├── *.dll                 ← libs do MuMain
├── play.bat              ← com placeholder seu-dominio.com
└── LEIA-ME.txt           ← instruções
```

**O player precisa, separado:**
- Os assets originais do MU S6 EP3 1.04D English (`Data/`, `Music/`, `Sound/`, `Object/`, `Player/`, `Lang/` etc).

Ele extrai esse zip POR CIMA dessas pastas → roda `play.bat`.

## Pré-edição do play.bat antes de distribuir

Se quiser poupar o player de editar o `.bat`, edita você mesmo o `play.bat` deste diretório antes de rodar a CI:

```diff
-SET SERVER=seu-dominio.com
+SET SERVER=mu.porcaria.gg
```

Commit, push, dispara CI de novo. O zip já sai com o IP correto.

## Quando o build quebrar

MuMain está em desenvolvimento ativo — `main` pode não compilar num dado dia. O que fazer:

1. **Pinha um commit conhecido** que funciona: dispara o workflow passando `mumain_ref=<sha>`.
2. **Olha os logs do step "Build (Release)"** — geralmente é dependência faltando ou erro de C++ recém-introduzido.
3. **Reporta upstream**: <https://github.com/sven-n/MuMain/issues>

## Custos

- Repos públicos no GitHub: Actions Windows são **grátis** (com limite mensal generoso).
- Repo privado: Windows runner gasta minutos **2x mais rápido** que Linux (1 min real = 2 min de quota).
