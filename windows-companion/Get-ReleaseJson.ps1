param(
    [uri]$Url = 'https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases.atom',
    [int]$TimeoutMilliseconds = 6000
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$handler = [Net.Http.HttpClientHandler]::new()
$client = $null
try {
    # Windows Internet Options include the system proxy and PAC configuration.
    # Explicit environment variables are useful when the proxy app does not set them.
    $proxyAddress = @($env:HTTPS_PROXY, $env:https_proxy, $env:ALL_PROXY, $env:all_proxy) |
        Where-Object { $_ } | Select-Object -First 1
    $noProxy = @($env:NO_PROXY, $env:no_proxy) | Where-Object { $_ } | Select-Object -First 1
    $bypass = $false
    if ($noProxy) {
        foreach ($entry in ($noProxy -split ',')) {
            $hostPattern = $entry.Trim().ToLowerInvariant()
            if ($hostPattern -eq '*' -or $hostPattern -eq $Url.Host.ToLowerInvariant() -or
                ($hostPattern.StartsWith('.') -and $Url.Host.ToLowerInvariant().EndsWith($hostPattern))) {
                $bypass = $true; break
            }
        }
    }
    if ($bypass) { $handler.UseProxy = $false }
    elseif ($proxyAddress) {
        if ($proxyAddress -notmatch '^[a-z]+://') { $proxyAddress = 'http://' + $proxyAddress }
        $proxyUri = [uri]$proxyAddress
        if ($proxyUri.Scheme -notin @('http','https')) { throw 'Unsupported proxy scheme' }
        $handler.Proxy = [Net.WebProxy]::new($proxyUri)
    } else {
        $handler.Proxy = [Net.WebRequest]::GetSystemWebProxy()
    }
    $handler.DefaultProxyCredentials = [Net.CredentialCache]::DefaultCredentials
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromMilliseconds($TimeoutMilliseconds)
    $atomUrl = 'https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases.atom'
    $sources = @($Url)
    if ($Url.AbsoluteUri -eq $atomUrl) {
        $sources += [uri]'https://api.github.com/repos/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases?per_page=30'
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $lastError = 'ERROR|NETWORK'
    foreach ($source in $sources) {
        $remaining = $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds
        if ($remaining -lt 200) { break }
        $budget = if ($sources.Count -gt 1 -and $source.AbsoluteUri -eq $atomUrl) {
            [Math]::Min(3500, $remaining)
        } else { $remaining }
        $request = $null; $response = $null; $stream = $null; $buffer = $null; $cancellation = $null
        try {
            $cancellation = [Threading.CancellationTokenSource]::new()
            $cancellation.CancelAfter($budget)
            $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $source)
            $request.Headers.UserAgent.ParseAdd('BJUT-YanXiaoBei-update-check')
            $request.Headers.Accept.ParseAdd($(if ($source.AbsoluteUri -eq $atomUrl) { 'application/atom+xml' } else { 'application/vnd.github+json' }))
            $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cancellation.Token).GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                $lastError = 'ERROR|HTTP|' + [int]$response.StatusCode
                continue
            }
            if ($response.Content.Headers.ContentLength -gt 524288) { throw 'Response too large' }
            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $buffer = [IO.MemoryStream]::new()
            $chunk = [byte[]]::new(8192)
            while (($read = $stream.ReadAsync($chunk, 0, $chunk.Length, $cancellation.Token).GetAwaiter().GetResult()) -gt 0) {
                if ($buffer.Length + $read -gt 524288) { throw 'Response too large' }
                $buffer.Write($chunk, 0, $read)
            }
            # Base64 is ASCII, so the parent Node process is independent of the PS 5.1 code page.
            $prefix = if ($source.AbsoluteUri -eq $atomUrl) { 'ATOM|' } else { '' }
            [Console]::WriteLine($prefix + [Convert]::ToBase64String($buffer.ToArray()))
            return
        } catch [System.Threading.Tasks.TaskCanceledException] {
            $lastError = 'ERROR|TIMEOUT'
        } catch {
            $lastError = 'ERROR|NETWORK'
        } finally {
            if ($buffer) { $buffer.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($response) { $response.Dispose() }
            if ($request) { $request.Dispose() }
            if ($cancellation) { $cancellation.Dispose() }
        }
    }
    [Console]::WriteLine($lastError)
} catch {
    [Console]::WriteLine('ERROR|NETWORK')
} finally {
    if ($client) { $client.Dispose() } else { $handler.Dispose() }
}
