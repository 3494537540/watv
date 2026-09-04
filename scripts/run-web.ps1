# 灰火 Web（Edge）本地调试
# 使用本地 CanvasKit，避免国内 CDN Failed to fetch 白屏
Set-Location $PSScriptRoot\..
flutter run -d edge --no-web-resources-cdn @args
