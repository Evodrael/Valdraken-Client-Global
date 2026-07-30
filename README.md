# Valdraken — Client Global (distribuição)

Repositório de **distribuição** do Client Global. Os players não clonam isto: o
`ValdrakenLauncherGlobal.exe` lê o `manifest.json` daqui e baixa cada arquivo do
`raw.githubusercontent.com`.

Este repositório é **gerado**, nunca editado à mão. A fonte é a pasta do client
(`C:\Valdraken-Client-Global-Final`) e o script `publish-global.ps1`.

---

## Publicar uma atualização

```powershell
powershell -ExecutionPolicy Bypass -File C:\Valdraken-Client-Global-Repo\publish-global.ps1 -Version 15.24.01
```

Depois:

```powershell
git add -A; git commit -m "client global 15.24.01"; git push
```

Só isso. O launcher detecta no próximo start dos players.

> Suba a versão em **todo** release. O launcher usa o `version.txt` como atalho: se a
> versão não mudar, ele nem baixa o `manifest.json` e os players não recebem a atualização.

Para conferir o repositório contra o manifest sem escrever nada:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Valdraken-Client-Global-Repo\publish-global.ps1 -Check
```

---

## O que o script resolve

### 1. O limite de 100 MB do GitHub

O GitHub recusa no push qualquer arquivo individual acima de 100 MB. O client de OTC passa
com mais de 1 GB porque nenhum arquivo dele chega a 40 MB — o limite é **por arquivo**, não
por repositório. Aqui existe um caso acima do limite:

```
bin\Qt6WebEngineCore.dll   189 MB   ->   bin/Qt6WebEngineCore.dll.gz   77 MB
```

Todo arquivo acima de 95 MB é publicado em GZip e remontado pelo launcher, com SHA256
conferido antes e depois de descomprimir. O `.gz` só é regerado quando o arquivo de origem
muda, então ele não repolui o histórico do git a cada release.

Se algum dia um arquivo passar de 100 MB **mesmo comprimido**, o script aborta com uma
mensagem explícita — nesse caso o arquivo precisa sair do repositório e ir para GitHub
Releases (limite de 2 GB por asset).

### 2. Dados pessoais e de runtime

A pasta do client contém coisas que **não podem** ser distribuídas. O script exclui por
lista explícita:

| Excluído | Motivo |
|---|---|
| `conf/clientoptions.json` | contém o `loginEmailAddress` da sua conta |
| `screenshots/` | 95 MB de screenshots pessoais |
| `minimap/` | minimapa explorado (cada player tem o seu) |
| `characterdata/` | configs por personagem |
| `cache/`, `crashdump/`, `log/` | estado de runtime |
| `*bak*` | backups de desenvolvimento |

O `conf/config.ini` **é** publicado — é ele que aponta o client para
`valdraken.com.br/login.php`.

### 3. Arquivos órfãos

Os assets têm o hash no nome (`appearances-<hash>.dat`), então uma atualização de conteúdo
cria um arquivo novo em vez de alterar o antigo. O script remove daqui o que não está mais
na pasta de origem, senão o repositório só cresce.

---

## Números do release atual

| | |
|---|---|
| Arquivos publicados | 10.256 |
| Tamanho no disco do player | 651,8 MB |
| Download (com o gzip) | 539,6 MB |
| Maior arquivo do repo | 76,9 MB (`bin/Qt6WebEngineCore.dll.gz`) |

---

## `.gitattributes`

O arquivo tem `* -text` e **isso não pode mudar**. Este repositório é distribuído por
hash: se o git converter quebra de linha (LF ↔ CRLF) em qualquer arquivo, os bytes servidos
pelo raw deixam de bater com o `sha256` do manifest e o launcher entra em loop de download.

---

## Atenção: o client tem um updater próprio

O Client Global traz um `assets.json` na raiz, que é o formato do **patcher nativo** dele
(`url` → `.lzma`, `packedhash`/`unpackedhash`, `localfile`). Ou seja, o client sabe se
auto-atualizar por outro caminho, apontando para o content server da CIP. Se em algum
momento os assets começarem a mudar sozinhos ou a voltar depois de uma atualização do
launcher, é aí que se deve olhar primeiro.
