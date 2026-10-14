# Draws the three white glow pictures used by the reveal screens (tinted in the game):
#   FxRays.png    1024 x 1024  a sunburst: 12 tapering rays that fade out towards the edge
#   FxGlow.png     512 x  512  a soft round glow
#   FxSparkle.png  256 x  256  a four-pointed twinkle star
# They are written into ..\ui-icons, white with see-through edges.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path (Split-Path -Parent $here) 'ui-icons'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class FxDraw
{
    static double Smooth(double a, double b, double x)
    {
        double t = Math.Max(0.0, Math.Min(1.0, (x - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }

    static void Save(double[] alpha, int size, string path)
    {
        Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        BitmapData data = bmp.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        byte[] bytes = new byte[size * size * 4];
        for (int i = 0; i < size * size; i++)
        {
            double a = Math.Max(0.0, Math.Min(1.0, alpha[i]));
            bytes[i * 4 + 0] = 255;
            bytes[i * 4 + 1] = 255;
            bytes[i * 4 + 2] = 255;
            bytes[i * 4 + 3] = (byte)Math.Round(a * 255);
        }
        Marshal.Copy(bytes, 0, data.Scan0, bytes.Length);
        bmp.UnlockBits(data);
        bmp.Save(path, ImageFormat.Png);
        bmp.Dispose();
    }

    // rays: 16 wedges, each about 45% of its slice wide, with soft sides; bright near the
    // middle and fading to nothing at the edge. The very middle is left soft (a glow sits there).
    public static void Rays(string path, int size, int count)
    {
        double[] alpha = new double[size * size];
        double slice = 2 * Math.PI / count;
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                double dx = (x + 0.5) / size - 0.5;
                double dy = (y + 0.5) / size - 0.5;
                double r = Math.Sqrt(dx * dx + dy * dy) / 0.5;
                double angle = Math.Atan2(dy, dx) + Math.PI;
                double inSlice = (angle % slice) / slice; // 0..1 across one slice
                double fromMiddle = Math.Abs(inSlice - 0.5) * 2; // 0 at the ray's middle, 1 between rays
                double ray = 1 - Smooth(0.40, 0.62, fromMiddle);
                double fade = Math.Pow(Math.Max(0.0, 1 - r), 1.6);
                double centre = Smooth(0.0, 0.12, r);
                alpha[y * size + x] = ray * fade * (0.35 + 0.65 * centre);
            }
        }
        Save(alpha, size, path);
    }

    public static void Glow(string path, int size)
    {
        double[] alpha = new double[size * size];
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                double dx = (x + 0.5) / size - 0.5;
                double dy = (y + 0.5) / size - 0.5;
                double r = Math.Sqrt(dx * dx + dy * dy) / 0.5;
                alpha[y * size + x] = Math.Pow(Math.Max(0.0, 1 - r), 2.2);
            }
        }
        Save(alpha, size, path);
    }

    // a twinkle: two thin crossing streaks that taper to points, and a small bright core
    public static void Sparkle(string path, int size)
    {
        double[] alpha = new double[size * size];
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                double u = ((x + 0.5) / size - 0.5) * 2;
                double v = ((y + 0.5) / size - 0.5) * 2;
                double au = Math.Abs(u), av = Math.Abs(v);
                double across = Math.Max(0.0, 1 - au);
                double down = Math.Max(0.0, 1 - av);
                double streakH = Math.Pow(across, 1.8) * Math.Exp(-Math.Pow(av / (0.09 * across + 0.012), 2));
                double streakV = Math.Pow(down, 1.8) * Math.Exp(-Math.Pow(au / (0.09 * down + 0.012), 2));
                double r = Math.Sqrt(u * u + v * v);
                double core = Math.Exp(-Math.Pow(r / 0.15, 2));
                double halo = 0.18 * Math.Exp(-Math.Pow(r / 0.32, 2));
                alpha[y * size + x] = Math.Max(Math.Max(streakH, streakV), Math.Max(core, halo));
            }
        }
        Save(alpha, size, path);
    }
}
'@

[FxDraw]::Rays((Join-Path $out 'FxRays.png'), 1024, 12)
[FxDraw]::Glow((Join-Path $out 'FxGlow.png'), 512)
[FxDraw]::Sparkle((Join-Path $out 'FxSparkle.png'), 256)
Get-ChildItem $out -Filter 'Fx*.png' | ForEach-Object { "{0}  {1:N0} bytes" -f $_.Name, $_.Length }
