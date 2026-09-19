# 简易静态文件服务器（仅供本地视觉检查用）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File tools/serve_artifacts.ps1 [端口] [根目录]
param(
    [int]$Port = 8765,
    [string]$Root = "artifacts"
)
$absRoot = Join-Path (Get-Location) $Root
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "Serving $absRoot at http://127.0.0.1:$Port/ (Ctrl+C to stop)"
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
        $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/')) -replace '/','\'
        $file = Join-Path $absRoot $rel
        if ((Test-Path $file -PathType Leaf) -and ($file.StartsWith($absRoot))) {
            $bytes = [IO.File]::ReadAllBytes($file)
            $ctx.Response.ContentType = "image/png"
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $ctx.Response.StatusCode = 404
        }
    } catch { $ctx.Response.StatusCode = 500 }
    finally { $ctx.Response.Close() }
}
