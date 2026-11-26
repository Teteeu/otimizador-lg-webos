$ErrorActionPreference = 'Stop'

function ConvertTo-LgLocalAddress {
    param([Parameter(Mandatory)][string]$Address)

    $parsed = $null
    if ($Address -notmatch '^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$' -or
        -not [Net.IPAddress]::TryParse($Address, [ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'Informe o endereço IPv4 local exibido na TV.'
    }

    $octets = $parsed.GetAddressBytes()
    if ($octets[0] -eq 10 -or
        ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
        ($octets[0] -eq 192 -and $octets[1] -eq 168)) {
        return $parsed.ToString()
    }
    throw 'Use um endereço privado da rede local da TV.'
}

function Open-LgSocket {
    param([uri]$Uri)

    $socket = [Net.WebSockets.ClientWebSocket]::new()
    $socket.Options.Proxy = $null
    $timeout = [Threading.CancellationTokenSource]::new(5000)
    try {
        $socket.ConnectAsync($Uri, $timeout.Token).GetAwaiter().GetResult()
        return $socket
    } catch {
        $socket.Dispose()
        throw 'A TV não respondeu. Confira o IP, a rede local e se a TV está ligada.'
    } finally {
        $timeout.Dispose()
    }
}

function Send-LgFrame {
    param($Socket, [string]$Text)

    $timeout = [Threading.CancellationTokenSource]::new(5000)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $Socket.SendAsync(
            [ArraySegment[byte]]::new($bytes),
            [Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            $timeout.Token
        ).GetAwaiter().GetResult()
    } finally {
        $timeout.Dispose()
    }
}

function Read-LgFrame {
    param($Socket, [int]$Seconds)

    $timeout = [Threading.CancellationTokenSource]::new($Seconds * 1000)
    $stream = [IO.MemoryStream]::new()
    $buffer = [byte[]]::new(8192)
    try {
        do {
            $message = $Socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), $timeout.Token).GetAwaiter().GetResult()
            if ($message.MessageType -ne [Net.WebSockets.WebSocketMessageType]::Text) {
                throw 'A TV encerrou a comunicação.'
            }
            $stream.Write($buffer, 0, $message.Count)
            if ($stream.Length -gt 2097152) { throw 'A resposta da TV excedeu o tamanho esperado.' }
        } until ($message.EndOfMessage)

        [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json -AsHashtable
    } finally {
        $stream.Dispose()
        $timeout.Dispose()
    }
}

function Invoke-LgRequest {
    param($Connection, [string]$Path, [hashtable]$Payload = @{})

    $id = [Guid]::NewGuid().ToString('N')
    $request = @{id=$id; type='request'; uri=('ssap://' + $Path); payload=$Payload}
    Send-LgFrame $Connection.Socket ($request | ConvertTo-Json -Depth 12 -Compress)

    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        $left = [Math]::Max(1, [int][Math]::Ceiling(5 - $watch.Elapsed.TotalSeconds))
        $reply = Read-LgFrame $Connection.Socket $left
        if ($reply.id -eq $id) {
            $errorCode = [regex]::Match([string]$reply.error, '^\d{3}').Value
            return [pscustomobject]@{
                Ok = ($reply.type -eq 'response' -and $reply.payload.returnValue -ne $false)
                Data = $reply.payload
                ErrorCode = $errorCode
            }
        }
    } while ($watch.Elapsed.TotalSeconds -lt 5)
    throw 'A TV não devolveu o resultado da operação.'
}

function Connect-LgTv {
    param([string]$Address, [string]$KeyFile, [switch]$Remember)

    $ip = ConvertTo-LgLocalAddress $Address
    $socket = Open-LgSocket ([uri]"ws://${ip}:3000/")
    $connection = [pscustomobject]@{Socket=$socket; Address=$ip; Model=''; PlatformVersion=''}
    try {
        $hello = @{id='hello'; type='hello'; payload=@{appName='Otimizador LG webOS'; appId='local.lgwebos.optimizer'}}
        Send-LgFrame $socket ($hello | ConvertTo-Json -Depth 6 -Compress)
        $device = Read-LgFrame $socket 5
        if ($device.type -ne 'hello') { throw 'A TV não respondeu ao protocolo webOS.' }

        $info = Invoke-LgRequest $connection 'system/getSystemInfo'
        $model = [string]$info.Data.modelName
        if ($model -notmatch '^[A-Za-z0-9 ._-]{1,55}$') { throw 'Não foi possível verificar o modelo da LG.' }
        $connection.Model = $model
        $platformVersion = [string]$device.payload.deviceOSVersion
        if ($platformVersion -match '^[A-Za-z0-9 ._()-]{1,55}$') { $connection.PlatformVersion = $platformVersion }
        Write-Host "TV encontrada na rede local: $model"

        $manifest = @{
            manifestVersion = 1
            localizedAppNames = @{''='Otimizador LG webOS'}
            permissions = @('READ_INSTALLED_APPS','READ_SETTINGS','WRITE_SETTINGS','CONTROL_INPUT_JOYSTICK','CONTROL_MOUSE_AND_KEYBOARD')
        }
        $pair = @{pairingType='PROMPT'; forcePairing=$false; manifest=$manifest}
        if ($KeyFile -and (Test-Path -LiteralPath $KeyFile -PathType Leaf)) {
            $saved = ConvertTo-SecureString -String ((Get-Content -LiteralPath $KeyFile -Raw).Trim())
            $pair['client-key'] = [Net.NetworkCredential]::new('', $saved).Password
        }

        Write-Host 'Se aparecer o aviso de conexão, selecione Permitir na TV.'
        $registration = @{id='register'; type='register'; payload=$pair}
        Send-LgFrame $socket ($registration | ConvertTo-Json -Depth 10 -Compress)
        $reply = Read-LgFrame $socket 15
        if ($reply.type -eq 'response' -and $reply.payload.pairingType -eq 'PROMPT') {
            $reply = Read-LgFrame $socket 55
        }
        if ($reply.type -ne 'registered') {
            throw 'O pareamento está pendente ou foi recusado. Veja o aviso na TV e execute de novo.'
        }
        if ($Remember -and $reply.payload['client-key']) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $KeyFile) -Force | Out-Null
            ConvertTo-SecureString -String $reply.payload['client-key'] -AsPlainText -Force |
                ConvertFrom-SecureString |
                Set-Content -LiteralPath $KeyFile -NoNewline
        }
        return $connection
    } catch {
        $socket.Dispose()
        throw
    }
}

function Get-LgApps {
    param($Connection)

    $result = Invoke-LgRequest $Connection 'com.webos.applicationManager/listApps'
    if (-not $result.Ok -or $null -eq $result.Data.apps) {
        throw 'A TV não disponibilizou a lista de apps para esta conexão.'
    }
    foreach ($app in @($result.Data.apps) | Sort-Object title) {
        $id = [string]$app.id
        if ($id -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,159}$') { continue }
        $title = [regex]::Replace([string]$app.title, '[\x00-\x1f\x7f-\x9f]', '').Trim()
        if (-not $title) { $title = $id }

        [pscustomobject]@{
            Name = $title
            Id = $id
            CanRemove = ($app.removable -is [bool] -and $app.removable -and
                $app.systemApp -is [bool] -and -not $app.systemApp)
            System = ($app.systemApp -is [bool] -and $app.systemApp)
        }
    }
}

function Get-LgSetting {
    param($Connection, [string]$Category, [string]$Key)

    $result = Invoke-LgRequest $Connection 'settings/getSystemSettings' @{category=$Category; keys=@($Key)}
    if ($result.Ok -and $result.Data.settings -and $result.Data.settings.Contains($Key)) {
        return [pscustomobject]@{Readable=$true; Value=$result.Data.settings[$Key]}
    }
    [pscustomobject]@{Readable=$false; Value=$null}
}

function Set-LgSetting {
    param($Connection, [string]$Category, [string]$Key, $Desired)

    $before = Get-LgSetting $Connection $Category $Key
    if (-not $before.Readable) { return 'Menu' }
    if ($Key -eq 'pictureMode' -and $before.Value -match '^(hdr|dolby|dv|hlg)') { return 'Menu' }

    $value = if ($before.Value -is [bool] -and $Desired -in 'on','off') { $Desired -eq 'on' } else { $Desired }
    if ($before.Value -eq $value) { return 'AlreadySet' }
    $settings = @{}
    $settings[$Key] = $value
    $reply = Invoke-LgRequest $Connection 'settings/setSystemSettings' @{category=$Category; settings=$settings}
    if (-not $reply.Ok) { return 'Menu' }

    for ($attempt=0; $attempt -lt 3; $attempt++) {
        Start-Sleep -Milliseconds 350
        $after = Get-LgSetting $Connection $Category $Key
        if ($after.Readable -and $after.Value -eq $value) { return 'Verified' }
    }
    return 'Unverified'
}

function Send-LgKey {
    param($Connection, [ValidateSet('UP','DOWN','LEFT','RIGHT','ENTER','BACK','HOME','MENU')][string]$Key)

    $result = Invoke-LgRequest $Connection 'com.webos.service.networkinput/getPointerInputSocket'
    $address = $null
    if (-not $result.Ok -or -not [uri]::TryCreate([string]$result.Data.socketPath, [UriKind]::Absolute, [ref]$address) -or
        $address.Scheme -ne 'ws' -or $address.Host -ne $Connection.Address -or $address.Port -ne 3000 -or $address.UserInfo) {
        throw 'A TV não forneceu um canal local de controle remoto.'
    }

    $socket = Open-LgSocket $address
    try {
        Send-LgFrame $socket "type:button`nname:$Key`n`n"
    } finally {
        $socket.Dispose()
    }
}

Export-ModuleMember -Function ConvertTo-LgLocalAddress, Connect-LgTv, Get-LgApps, Get-LgSetting, Set-LgSetting, Send-LgKey
