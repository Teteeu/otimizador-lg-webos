#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$IpTv,
    [switch]$LembrarPareamento,
    [switch]$SomenteAuditar
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/LgWebOs.psm1') -Force

$keys = @{
    h = 'HOME'
    m = 'MENU'
    w = 'UP'
    s = 'DOWN'
    a = 'LEFT'
    d = 'RIGHT'
    o = 'ENTER'
    b = 'BACK'
}

$quickStart = @{
    Category = 'option'
    Key = 'quickStart'
    Label = 'Início Rápido+'
    Value = 'off'
    Menu = 'Configurações → Todas as configurações → Geral → Início Rápido+'
    Advice = 'Desligar pode ajudar com memória e travamentos em alguns modelos. A partida a frio pode levar mais tempo.'
}
$picture = @{
    Category = 'picture'
    Key = 'pictureMode'
    Label = 'Modo de imagem'
    Menu = 'Configurações → Todas as configurações → Imagem → Seleção do modo'
}
$profiles = [ordered]@{
    '1' = @{Name='Desempenho do sistema'; Step=$quickStart}
    '2' = @{Name='Jogos e menor atraso'; Step=$picture + @{Value='game'; Advice='Na entrada dos jogos, selecione Jogo ou Otimizador de Jogos, conforme o modelo.'}}
    '3' = @{Name='Qualidade para filmes'; Step=$picture + @{Value='cinema'; Advice='Para filmes em SDR, selecione Cinema, quando disponível.'}}
    '4' = @{Name='Equilibrado'; Step=$picture + @{Value='standard'; Advice='Selecione Padrão para manter um perfil geral de imagem.'}}
    '5' = @{Name='Somente verificar os ajustes'; Step=$null}
}

function Show-ControlHelp {
    Write-Host 'Controle pelo PC | H Início, M Configurações, W A S D setas, O OK, B Voltar.'
    Write-Host 'Você também pode usar o controle físico da TV.'
}

function Show-SettingAudit {
    param($Connection, $Setting)

    $result = Get-LgSetting $Connection $Setting.Category $Setting.Key
    if ($result.Readable) {
        Write-Host "$($Setting.Label) está em $($result.Value)."
    } else {
        Write-Host "Confira $($Setting.Label) no menu da TV."
    }
}

function Invoke-MenuSetting {
    param($Connection, $Setting)

    Write-Host $Setting.Menu
    Write-Host $Setting.Advice
    Show-ControlHelp
    do {
        $action = (Read-Host 'Tecla do controle, V para conferir ou P para pular').Trim().ToLowerInvariant()
        if ($keys.ContainsKey($action)) { Send-LgKey $Connection $keys[$action] }
        if ($action -eq 'v') {
            $readback = Get-LgSetting $Connection $Setting.Category $Setting.Key
            if ($readback.Readable) { Write-Host "A TV informa $($Setting.Label) em $($readback.Value)." }
            else { Write-Host 'O valor pode ser confirmado pelo indicador de seleção na tela da TV.' }
        }
    } until ($action -in 'v','p')
}

function Invoke-Profile {
    param($Connection)

    Write-Host ''
    Write-Host 'Qual é sua prioridade?'
    foreach ($entry in $profiles.GetEnumerator()) { Write-Host "$($entry.Key). $($entry.Value.Name)" }
    do {
        $choice = (Read-Host 'Escolha de 1 a 5').Trim()
    } until ($profiles.Contains($choice))

    $step = $profiles[$choice].Step
    if (-not $step) { return }
    Write-Host $step.Advice
    if ($choice -in '2','3','4') {
        $inputReady = Read-Host 'Abra na TV a entrada ou o conteúdo que quer ajustar. Digite S para aplicar o perfil'
        if ($inputReady -notmatch '^\s*[sS]\s*$') { return }
    }

    switch (Set-LgSetting $Connection $step.Category $step.Key $step.Value) {
        'Verified' { Write-Host "A TV confirmou $($step.Label) em $($step.Value)." }
        'AlreadySet' { Write-Host "$($step.Label) já está no valor escolhido." }
        'Unverified' {
            Write-Host 'A TV aceitou o pedido. Confira o valor que ficou aplicado.'
            Invoke-MenuSetting $Connection $step
        }
        'Menu' { Invoke-MenuSetting $Connection $step }
    }
}

function Get-AppSelection {
    param([object[]]$Available)

    for ($index=0; $index -lt $Available.Count; $index++) {
        Write-Host "$($index+1). $($Available[$index].Name)"
    }
    while ($true) {
        $response = (Read-Host 'Quais apps quer desinstalar? Separe os números por vírgulas ou pressione Enter para manter todos').Trim()
        if (-not $response) { return }
        $tokens = @($response -split '[,\s]+' | Where-Object {$_})
        $numbers = @(foreach ($token in $tokens) {
            $number = 0
            if ([int]::TryParse($token, [ref]$number) -and $number -ge 1 -and $number -le $Available.Count) { $number }
        })
        if ($tokens.Count -eq 0 -or $numbers.Count -ne $tokens.Count) {
            Write-Host 'Use apenas os números exibidos na lista de apps removíveis.'
            continue
        }
        foreach ($number in $numbers | Sort-Object -Unique) { $Available[$number-1] }
        return
    }
}

function Invoke-AppRemoval {
    param($Connection, [object[]]$Apps)

    $available = @($Apps | Where-Object CanRemove)
    if ($available.Count -eq 0) { Write-Host 'A TV não marcou nenhum app como removível.'; return }
    Write-Host ''
    Write-Host 'Apps que a TV permite remover'
    $selected = @(Get-AppSelection $available)
    if ($selected.Count -eq 0) { return }

    Write-Host ('Selecionados para remover: ' + ($selected.Name -join ', '))
    Write-Host 'Remover um app pode apagar os dados locais dele.'
    if ($selected.Id -contains 'com.palmdts.devmode') {
        Write-Host 'Remover Developer Mode pode também remover apps instalados por ele.'
    }
    if ((Read-Host 'Digite REMOVER para continuar pelo menu da TV').Trim() -ne 'REMOVER') { return }

    Show-ControlHelp
    Write-Host 'Abra Início, selecione o app e segure OK no controle da TV para editar. Em alguns modelos, use Editar lista de apps.'
    Write-Host 'Confirme o nome do app no aviso da TV antes de selecionar Excluir.'

    foreach ($app in $selected) {
        $remaining = @(Get-LgApps $Connection | Where-Object Id -eq $app.Id)
        if ($remaining.Count -eq 0) { Write-Host "$($app.Name) já está fora da lista."; continue }
        if ($remaining.Count -ne 1 -or -not $remaining[0].CanRemove) { Write-Host "$($app.Name) está bloqueado para remoção."; continue }
        Write-Host "App selecionado: $($app.Name)"
        do {
            $action = (Read-Host 'Tecla do controle, V para verificar a remoção ou P para pular').Trim().ToLowerInvariant()
            if ($keys.ContainsKey($action)) { Send-LgKey $Connection $keys[$action] }
            if ($action -eq 'v') {
                $remaining = @(Get-LgApps $Connection | Where-Object Id -eq $app.Id)
                if ($remaining.Count -eq 0) { Write-Host "Remoção de $($app.Name) confirmada na lista da TV."; break }
                Write-Host "$($app.Name) continua na lista. Confira o aviso da TV."
            }
        } until ($action -eq 'p')
    }
}

Write-Host 'Otimizador LG webOS'
Write-Host '1. Ligue a TV e conecte o PC e a TV à mesma rede de casa.'
Write-Host '2. Na TV, abra Configurações → Rede e anote o IPv4 da conexão ativa.'
Write-Host '3. Se o modelo tiver a opção LG Connect Apps, ligue-a. Depois confirme Permitir quando o aviso aparecer na TV.'
if (-not $IpTv) { $IpTv = Read-Host 'Digite o IPv4 que a TV mostrou' }
$address = ConvertTo-LgLocalAddress $IpTv.Trim()
$keyFile = $null
if ($LembrarPareamento) {
    if (-not $IsWindows) { throw 'Lembrar o pareamento usa a proteção de credenciais do Windows.' }
    $keyFile = Join-Path $PSScriptRoot ('.local/' + $address + '.dpapi')
}

$connection = $null
try {
    $connection = Connect-LgTv $address $keyFile -Remember:$LembrarPareamento
    if ($connection.PlatformVersion) { Write-Host "webOS informado pela TV: $($connection.PlatformVersion)" }
    $installed = @(Get-LgApps $connection)
    $installed | Select-Object Name,
        @{Name='Tipo'; Expression={ if ($_.System) {'Sistema'} else {'Instalado'} }},
        @{Name='Removível'; Expression={ if ($_.CanRemove) {'Sim'} else {'Protegido ou indisponível'} }} |
        Format-Table -AutoSize
    Show-SettingAudit $connection $quickStart
    Show-SettingAudit $connection $picture

    if (-not $SomenteAuditar) {
        Invoke-Profile $connection
        Invoke-AppRemoval $connection $installed
    }
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
} finally {
    if ($connection) { $connection.Socket.Dispose() }
}
