$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets\branding\app_icon.png'
$destinationPath = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'

# Export the approved PNG into Windows icon sizes without changing its design.
Add-Type -AssemblyName System.Drawing
if (-not ('SimpleCalendar.IconExporter' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

namespace SimpleCalendar {
    public static class IconExporter {
        public static void Export(string sourcePath, string destinationPath) {
            int[] sizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
            var frames = new List<byte[]>();
            using (var source = new Bitmap(sourcePath)) {
                foreach (int size in sizes) {
                    using (var bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb))
                    using (var graphics = Graphics.FromImage(bitmap))
                    using (var attributes = new ImageAttributes())
                    using (var stream = new MemoryStream()) {
                        graphics.Clear(Color.Transparent);
                        graphics.CompositingMode = CompositingMode.SourceCopy;
                        graphics.CompositingQuality = CompositingQuality.HighQuality;
                        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        attributes.SetWrapMode(WrapMode.TileFlipXY);
                        graphics.DrawImage(source, new Rectangle(0, 0, size, size),
                            0, 0, source.Width, source.Height, GraphicsUnit.Pixel, attributes);
                        bitmap.Save(stream, ImageFormat.Png);
                        frames.Add(stream.ToArray());
                    }
                }
            }
            using (var stream = File.Create(destinationPath))
            using (var writer = new BinaryWriter(stream)) {
                writer.Write((ushort)0);
                writer.Write((ushort)1);
                writer.Write((ushort)sizes.Length);
                uint offset = (uint)(6 + 16 * sizes.Length);
                for (int index = 0; index < sizes.Length; index++) {
                    writer.Write((byte)(sizes[index] == 256 ? 0 : sizes[index]));
                    writer.Write((byte)(sizes[index] == 256 ? 0 : sizes[index]));
                    writer.Write((byte)0);
                    writer.Write((byte)0);
                    writer.Write((ushort)1);
                    writer.Write((ushort)32);
                    writer.Write((uint)frames[index].Length);
                    writer.Write(offset);
                    offset += (uint)frames[index].Length;
                }
                foreach (var frame in frames) writer.Write(frame);
            }
        }
    }
}
'@
}
[SimpleCalendar.IconExporter]::Export($sourcePath, $destinationPath)
Write-Output "Windows icon updated: $destinationPath"
