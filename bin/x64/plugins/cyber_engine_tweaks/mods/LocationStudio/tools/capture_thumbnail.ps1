param(
  [Parameter(Mandatory=$true)][string]$Output,
  [double]$Delay = 0.45
)
$ErrorActionPreference = 'Stop'
$ErrorFile = $Output + '.error'
try {
  if (Test-Path $ErrorFile) { Remove-Item -Force $ErrorFile }
  Start-Sleep -Milliseconds ([int]([Math]::Max(0.0, $Delay) * 1000))
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
  $g.Dispose()
  $side = [int]([Math]::Min($bounds.Width * 0.62, $bounds.Height * 0.72))
  if ($side -lt 64) { $side = [Math]::Min($bounds.Width, $bounds.Height) }
  $x = [int](($bounds.Width - $side) / 2)
  $y = [int](($bounds.Height - $side) / 2)
  $crop = New-Object System.Drawing.Bitmap $side, $side
  $cg = [System.Drawing.Graphics]::FromImage($crop)
  $cg.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0,0,$side,$side), (New-Object System.Drawing.Rectangle $x,$y,$side,$side), [System.Drawing.GraphicsUnit]::Pixel)
  $cg.Dispose(); $bmp.Dispose()
  $outBmp = New-Object System.Drawing.Bitmap 512,512
  $og = [System.Drawing.Graphics]::FromImage($outBmp)
  $og.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $og.DrawImage($crop,0,0,512,512)
  $og.Dispose(); $crop.Dispose()
  $dir=[System.IO.Path]::GetDirectoryName($Output)
  if ($dir) { [System.IO.Directory]::CreateDirectory($dir) | Out-Null }
  $tmp=$Output+'.tmp.png'
  $outBmp.Save($tmp,[System.Drawing.Imaging.ImageFormat]::Png)
  $outBmp.Dispose()
  Move-Item -Force $tmp $Output
  if (Test-Path $ErrorFile) { Remove-Item -Force $ErrorFile }
  exit 0
}
catch {
  try { [System.IO.File]::WriteAllText($ErrorFile, $_.Exception.Message) } catch {}
  exit 1
}
