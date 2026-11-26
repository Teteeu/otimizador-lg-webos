# Otimizador LG webOS

Assistente de terminal para conferir ajustes, escolher um perfil de uso e acompanhar a remoção de apps em uma TV LG pela rede local.

## Primeiro conecte a TV

1. Ligue a TV. Conecte o PC e a TV à mesma rede da sua casa. Uma rede de convidados pode bloquear a comunicação entre os aparelhos.
2. Na TV, abra **Configurações → Todas as configurações → Rede** e veja os detalhes da conexão Wi-Fi ou cabeada. Anote o endereço IPv4.
3. Se a TV mostrar a opção **LG Connect Apps**, ative-a. No PC, instale o PowerShell 7 e baixe este repositório. [Instalação do PowerShell](https://learn.microsoft.com/pt-br/powershell/scripting/install/installing-powershell-on-windows)
4. Abra o PowerShell 7 na pasta do projeto e rode o comando abaixo. Informe o endereço da TV e escolha **Permitir** no aviso que aparecer na tela.

```powershell
pwsh -NoProfile -File ./Optimize-LgTv.ps1
```

O projeto usa o controle de rede da LG. Ele é voltado a TVs que disponibilizam SSAP pela porta local 3000. Os recursos e o caminho dos menus variam conforme o modelo e a versão do webOS. [Connect SDK da LG](https://connectsdk.com/en/latest/apis-and/and-webostvservice.html)

## Escolha o que ajustar

O assistente mostra o modelo, lê a lista de apps e tenta consultar **Início Rápido+** e **Modo de imagem**. Depois ele pergunta sua prioridade.

| Prioridade | Ajuste |
| --- | --- |
| Desempenho do sistema | Desliga Início Rápido+ quando a TV permite. A LG orienta esse ajuste em casos de falta de memória ou apps travando. A partida a frio pode demorar mais. |
| Jogos e menor atraso | Tenta selecionar o modo Jogo na entrada que você abriu para ajustar. |
| Qualidade para filmes | Tenta selecionar Cinema para filmes em SDR na entrada ou conteúdo escolhido. |
| Equilibrado | Tenta selecionar Padrão para uso geral. |
| Somente verificar os ajustes | Mostra a auditoria e segue para a escolha de apps. |

Quando o webOS permite leitura e escrita, o assistente aplica o ajuste e lê o valor novamente. Se o modelo exigir o menu da TV, o programa oferece o caminho e um controle remoto por teclas no PC. Ajuste modos HDR e Dolby Vision pelo menu específico do conteúdo. [Orientação da LG sobre memória e Início Rápido+](https://www.lg.com/us/support/help-library/lg-tv-memory-shortage-error-app-won-t-run-CT10000018-20154522128317)

## Escolha os apps para remover

1. Selecione os números dos apps que a TV indicou como removíveis ou pressione Enter para manter todos.
2. Confira os nomes. O assistente acompanha a exclusão pelo editor de apps da LG. Vá em **Início**, segure **OK** sobre o app ou abra **Editar lista de apps**, conforme o seu modelo.
3. Confirme a exclusão na TV e pressione **V** no programa. Ele consulta a lista novamente para verificar se o app saiu.

Apps que vieram instalados podem ser removíveis. Componentes protegidos pelo firmware ficam na lista com essa indicação. Remover apps que você não usa libera armazenamento. [Como remover apps pela LG](https://www.lg.com/br/suporte/suporte-ao-producto/solucionar-problemas/help-library/cs-CT52001752-20154523926069/)

## Opções do comando

```powershell
pwsh -NoProfile -File ./Optimize-LgTv.ps1 -SomenteAuditar
pwsh -NoProfile -File ./Optimize-LgTv.ps1 -IpTv 192.168.0.42 -LembrarPareamento
```

**SomenteAuditar** consulta a TV e lista o que ela disponibiliza. **LembrarPareamento** é opcional no Windows e guarda a chave de conexão protegida para o usuário atual em `.local/`. Para refazer o pareamento, volte a executar o programa sem essa opção.

Mantenha a TV ligada e deixe o aviso de pareamento visível. Se o endereço mudar, consulte novamente as configurações de rede da TV. Na exclusão em versões antigas, mantenha **OK** pressionado no controle físico para abrir o editor.
