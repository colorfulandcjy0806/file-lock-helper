#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class FileLockIconArtwork
{
    private static GraphicsPath RoundedRect(float x, float y, float width, float height, float radius)
    {
        float d = radius * 2f;
        var path = new GraphicsPath();
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + width - d, y, d, d, 270, 90);
        path.AddArc(x + width - d, y + height - d, d, d, 0, 90);
        path.AddArc(x, y + height - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static Bitmap DrawIcon()
    {
        var bmp = new Bitmap(256, 256, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);

            using (GraphicsPath tile = RoundedRect(8, 8, 240, 240, 48))
            using (var bg = new LinearGradientBrush(new Rectangle(8, 8, 240, 240),
                Color.FromArgb(18, 51, 91), Color.FromArgb(33, 151, 193), 38f))
            {
                g.FillPath(bg, tile);
                g.SetClip(tile);
                using (var shine = new SolidBrush(Color.FromArgb(28, 255, 255, 255)))
                    g.FillEllipse(shine, 34, -79, 255, 190);
                using (var shade = new SolidBrush(Color.FromArgb(24, 3, 25, 57)))
                    g.FillEllipse(shade, -45, 155, 330, 180);
                g.ResetClip();
            }

            using (var shadow = new SolidBrush(Color.FromArgb(45, 5, 24, 48)))
            using (GraphicsPath pageShadow = RoundedRect(49, 42, 151, 181, 15))
                g.FillPath(shadow, pageShadow);

            PointF[] page = new PointF[] {
                new PointF(52, 31), new PointF(148, 31), new PointF(199, 82),
                new PointF(199, 214), new PointF(52, 214)
            };
            using (GraphicsPath pagePath = new GraphicsPath())
            using (var paper = new LinearGradientBrush(new Rectangle(52, 31, 147, 183),
                Color.White, Color.FromArgb(231, 244, 250), 90f))
            using (var edge = new Pen(Color.FromArgb(220, 255, 255, 255), 2f))
            {
                pagePath.AddPolygon(page);
                pagePath.CloseFigure();
                g.FillPath(paper, pagePath);
                g.DrawPath(edge, pagePath);
            }

            PointF[] fold = new PointF[] {
                new PointF(148, 32), new PointF(148, 81), new PointF(198, 81)
            };
            using (var foldBrush = new SolidBrush(Color.FromArgb(197, 226, 241)))
            using (var foldLine = new Pen(Color.FromArgb(174, 208, 227), 2f))
            {
                g.FillPolygon(foldBrush, fold);
                g.DrawLine(foldLine, 148, 32, 148, 81);
                g.DrawLine(foldLine, 148, 81, 198, 81);
            }

            using (var linePen = new Pen(Color.FromArgb(102, 146, 177), 8f))
            {
                linePen.StartCap = LineCap.Round; linePen.EndCap = LineCap.Round;
                g.DrawLine(linePen, 76, 103, 160, 103);
                g.DrawLine(linePen, 76, 125, 143, 125);
                g.DrawLine(linePen, 76, 147, 128, 147);
            }

            using (var badgeShadow = new SolidBrush(Color.FromArgb(60, 8, 38, 64)))
                g.FillEllipse(badgeShadow, 119, 131, 116, 116);
            using (var badgeOuter = new SolidBrush(Color.White))
                g.FillEllipse(badgeOuter, 116, 125, 116, 116);
            using (var badge = new LinearGradientBrush(new Rectangle(122, 131, 104, 104),
                Color.FromArgb(34, 191, 166), Color.FromArgb(9, 143, 157), 45f))
                g.FillEllipse(badge, 122, 131, 104, 104);

            // A simple white padlock with a visible keyhole.
            using (var shackle = new Pen(Color.White, 10f))
            {
                shackle.StartCap = LineCap.Round; shackle.EndCap = LineCap.Round;
                g.DrawArc(shackle, 151, 148, 46, 48, 180, 180);
            }
            using (GraphicsPath body = RoundedRect(145, 174, 59, 44, 8))
            using (var bodyBrush = new LinearGradientBrush(new Rectangle(145, 174, 59, 44),
                Color.White, Color.FromArgb(225, 246, 249), 90f))
                g.FillPath(bodyBrush, body);
            using (var hole = new SolidBrush(Color.FromArgb(7, 124, 139)))
            {
                g.FillEllipse(hole, 170, 187, 9, 9);
                g.FillRectangle(hole, 173, 193, 4, 10);
            }
        }
        return bmp;
    }

    public static void Create(string directory)
    {
        Directory.CreateDirectory(directory);
        using (Bitmap baseImage = DrawIcon())
        {
            baseImage.Save(Path.Combine(directory, "FileLockHelper.png"), ImageFormat.Png);
            int[] sizes = new int[] { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
            var pngs = new List<byte[]>();
            foreach (int size in sizes)
            {
                using (var resized = new Bitmap(size, size, PixelFormat.Format32bppArgb))
                using (Graphics g = Graphics.FromImage(resized))
                using (var ms = new MemoryStream())
                {
                    g.SmoothingMode = SmoothingMode.HighQuality;
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(baseImage, new Rectangle(0, 0, size, size));
                    resized.Save(ms, ImageFormat.Png);
                    pngs.Add(ms.ToArray());
                }
            }

            using (var output = new MemoryStream())
            using (var writer = new BinaryWriter(output))
            {
                writer.Write((ushort)0);
                writer.Write((ushort)1);
                writer.Write((ushort)pngs.Count);
                int offset = 6 + pngs.Count * 16;
                for (int i = 0; i < sizes.Length; i++)
                {
                    writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                    writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                    writer.Write((byte)0);
                    writer.Write((byte)0);
                    writer.Write((ushort)1);
                    writer.Write((ushort)32);
                    writer.Write((uint)pngs[i].Length);
                    writer.Write((uint)offset);
                    offset += pngs[i].Length;
                }
                foreach (byte[] png in pngs) writer.Write(png);
                File.WriteAllBytes(Path.Combine(directory, "FileLockHelper.ico"), output.ToArray());
            }
        }
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies @('System.dll', 'System.Core.dll', 'System.Drawing.dll')
[FileLockIconArtwork]::Create($PSScriptRoot)
Write-Host "图标已生成：$PSScriptRoot\FileLockHelper.ico"
