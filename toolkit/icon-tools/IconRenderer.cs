// Draws the UI pictures from the block lists in models.txt (see render-icons.ps1).
// Plain old C# on purpose: Windows PowerShell compiles it with the built-in compiler.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

public class IconPart
{
    public char Shape;
    public double SX, SY, SZ, PX, PY, PZ;
    public double[] R; // 3x3, row by row; null = not turned
    public string Hex;
    public double Alpha = 1;
    public bool Neon;
    public IconPart Clone() { return (IconPart)MemberwiseClone(); }
}

public class IconModel
{
    public string Name;
    public string Pre = "";
    public double Turn = 0, Tilt = 15;
    public List<IconPart> Parts = new List<IconPart>();
}

public class IconTri
{
    public double[] X = new double[3], Y = new double[3], D = new double[3];
    public double[] NX = new double[3], NY = new double[3], NZ = new double[3];
    public double Cr, Cg, Cb, Alpha;
    public bool Neon;
    public double Depth() { return (D[0] + D[1] + D[2]) / 3; }
}

public class IconImage
{
    public int Size;
    public float[] Rgba; // premultiplied, 0..1
    public float[] Cover; // how much of each pixel the model covers, ignoring see-through
}

public static class IconRenderer
{
    // light, in "screen" directions: from the left, from above, from the front
    static readonly double[] Light = Norm(new double[] { -0.40, 0.74, 0.54 });
    const double Ambient = 0.60, Diffuse = 0.46;

    static double Num(string s) { return double.Parse(s, CultureInfo.InvariantCulture); }

    static double[] Norm(double[] v)
    {
        double l = Math.Sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        return new double[] { v[0] / l, v[1] / l, v[2] / l };
    }

    static void Options(IconModel model, string[] tokens, int from)
    {
        for (int i = from; i < tokens.Length; i++)
        {
            string[] pair = tokens[i].Split('=');
            if (pair.Length != 2) continue;
            if (pair[0] == "pre") model.Pre = pair[1];
            else if (pair[0] == "turn") model.Turn = Num(pair[1]);
            else if (pair[0] == "tilt") model.Tilt = Num(pair[1]);
        }
    }

    public static List<IconModel> Load(string path)
    {
        List<IconModel> models = new List<IconModel>();
        Dictionary<string, IconModel> byName = new Dictionary<string, IconModel>();
        IconModel current = null;
        foreach (string raw in File.ReadAllLines(path))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line[0] == '#') continue;
            string[] t = line.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (t[0] == "M")
            {
                current = new IconModel();
                current.Name = t[1];
                Options(current, t, 2);
                models.Add(current);
                byName[current.Name] = current;
            }
            else if (t[0] == "V")
            {
                current = new IconModel();
                current.Name = t[1];
                IconModel source = byName[t[2]];
                current.Pre = source.Pre;
                string[] swap = t[3].Split('>');
                foreach (IconPart part in source.Parts)
                {
                    IconPart copy = part.Clone();
                    if (swap.Length == 2 && copy.Hex == swap[0]) copy.Hex = swap[1];
                    current.Parts.Add(copy);
                }
                Options(current, t, 4);
                models.Add(current);
                byName[current.Name] = current;
            }
            else
            {
                IconPart p = new IconPart();
                p.Shape = t[0][0];
                p.SX = Num(t[1]); p.SY = Num(t[2]); p.SZ = Num(t[3]);
                p.PX = Num(t[4]); p.PY = Num(t[5]); p.PZ = Num(t[6]);
                int i = 7;
                if (t[i] == "R")
                {
                    p.R = new double[9];
                    for (int k = 0; k < 9; k++) p.R[k] = Num(t[i + 1 + k]);
                    i += 10;
                }
                p.Hex = t[i]; i++;
                for (; i < t.Length; i++)
                {
                    if (t[i] == "n") p.Neon = true;
                    else if (t[i][0] == 't') p.Alpha = 1 - Num(t[i].Substring(1));
                }
                current.Parts.Add(p);
            }
        }
        return models;
    }

    // ---- turning a model into flat triangles on the screen ---------------------------------

    class View
    {
        public string Pre; public double CosTurn, SinTurn, CosTilt, SinTilt;

        // block space -> model space -> stood up -> turned -> screen (x right, y up, d towards the camera)
        public void Point(IconPart p, double lx, double ly, double lz, out double sx, out double sy, out double d)
        {
            double x, y, z;
            Rotate(p, lx, ly, lz, out x, out y, out z);
            Place(x + p.PX, y + p.PY, z + p.PZ, out sx, out sy, out d);
        }

        public void Normal(IconPart p, double lx, double ly, double lz, out double nx, out double ny, out double nz)
        {
            double x, y, z;
            Rotate(p, lx, ly, lz, out x, out y, out z);
            Place(x, y, z, out nx, out ny, out nz);
        }

        static void Rotate(IconPart p, double lx, double ly, double lz, out double x, out double y, out double z)
        {
            if (p.R == null) { x = lx; y = ly; z = lz; return; }
            x = p.R[0] * lx + p.R[1] * ly + p.R[2] * lz;
            y = p.R[3] * lx + p.R[4] * ly + p.R[5] * lz;
            z = p.R[6] * lx + p.R[7] * ly + p.R[8] * lz;
        }

        void Place(double x, double y, double z, out double sx, out double sy, out double d)
        {
            double a = x, b = y, c = z;
            if (Pre == "Y90") { a = z; b = y; c = -x; }       // +X becomes the front (-Z)
            else if (Pre == "Z90") { a = -y; b = x; c = z; }  // +X becomes up
            double wx = a * CosTurn + c * SinTurn;
            double wz = -a * SinTurn + c * CosTurn;
            double wy = b;
            sx = -wx;
            sy = wy * CosTilt + wz * SinTilt;
            d = wy * SinTilt - wz * CosTilt;
        }
    }

    static void AddTri(List<IconTri> tris, View view, IconPart p, double[] a, double[] b, double[] c, double[] na, double[] nb, double[] nc)
    {
        IconTri t = new IconTri();
        double[][] pts = new double[][] { a, b, c };
        double[][] nrm = new double[][] { na, nb, nc };
        for (int i = 0; i < 3; i++)
        {
            view.Point(p, pts[i][0], pts[i][1], pts[i][2], out t.X[i], out t.Y[i], out t.D[i]);
            view.Normal(p, nrm[i][0], nrm[i][1], nrm[i][2], out t.NX[i], out t.NY[i], out t.NZ[i]);
        }
        Color color = ColorTranslator.FromHtml("#" + p.Hex);
        t.Cr = color.R / 255.0; t.Cg = color.G / 255.0; t.Cb = color.B / 255.0;
        t.Alpha = p.Alpha; t.Neon = p.Neon;
        tris.Add(t);
    }

    static void AddQuad(List<IconTri> tris, View view, IconPart p, double[] a, double[] b, double[] c, double[] d, double[] n)
    {
        AddTri(tris, view, p, a, b, c, n, n, n);
        AddTri(tris, view, p, a, c, d, n, n, n);
    }

    static List<IconTri> Triangles(IconModel model)
    {
        View view = new View();
        view.Pre = model.Pre;
        view.CosTurn = Math.Cos(model.Turn * Math.PI / 180); view.SinTurn = Math.Sin(model.Turn * Math.PI / 180);
        view.CosTilt = Math.Cos(model.Tilt * Math.PI / 180); view.SinTilt = Math.Sin(model.Tilt * Math.PI / 180);
        List<IconTri> tris = new List<IconTri>();
        foreach (IconPart p in model.Parts)
        {
            double hx = p.SX / 2, hy = p.SY / 2, hz = p.SZ / 2;
            if (p.Shape == 'C')
            {
                // a cylinder lies along its own X axis
                double r = Math.Min(p.SY, p.SZ) / 2;
                const int Sides = 64;
                for (int i = 0; i < Sides; i++)
                {
                    double a0 = 2 * Math.PI * i / Sides, a1 = 2 * Math.PI * (i + 1) / Sides;
                    double y0 = Math.Cos(a0), z0 = Math.Sin(a0), y1 = Math.Cos(a1), z1 = Math.Sin(a1);
                    double[] n0 = new double[] { 0, y0, z0 }, n1 = new double[] { 0, y1, z1 };
                    double[] p00 = new double[] { -hx, y0 * r, z0 * r }, p01 = new double[] { hx, y0 * r, z0 * r };
                    double[] p10 = new double[] { -hx, y1 * r, z1 * r }, p11 = new double[] { hx, y1 * r, z1 * r };
                    AddTri(tris, view, p, p00, p01, p11, n0, n0, n1);
                    AddTri(tris, view, p, p00, p11, p10, n0, n1, n1);
                    double[] right = new double[] { 1, 0, 0 }, left = new double[] { -1, 0, 0 };
                    AddTri(tris, view, p, new double[] { hx, 0, 0 }, p01, p11, right, right, right);
                    AddTri(tris, view, p, new double[] { -hx, 0, 0 }, p00, p10, left, left, left);
                }
            }
            else
            {
                for (int axis = 0; axis < 3; axis++)
                {
                    for (int sign = -1; sign <= 1; sign += 2)
                    {
                        double[] n = new double[3]; n[axis] = sign;
                        int u = (axis + 1) % 3, v = (axis + 2) % 3;
                        double[] h = new double[] { hx, hy, hz };
                        double[][] corner = new double[4][];
                        int[][] offsets = new int[][] { new int[] { -1, -1 }, new int[] { 1, -1 }, new int[] { 1, 1 }, new int[] { -1, 1 } };
                        for (int k = 0; k < 4; k++)
                        {
                            corner[k] = new double[3];
                            corner[k][axis] = sign * h[axis];
                            corner[k][u] = offsets[k][0] * h[u];
                            corner[k][v] = offsets[k][1] * h[v];
                        }
                        AddQuad(tris, view, p, corner[0], corner[1], corner[2], corner[3], n);
                    }
                }
            }
        }
        return tris;
    }

    // ---- filling the triangles in -------------------------------------------------------------

    static void Fill(IconTri t, int w, double[] depth, float[] rgba, byte[] cover, bool solid)
    {
        double area = (t.X[1] - t.X[0]) * (t.Y[2] - t.Y[0]) - (t.X[2] - t.X[0]) * (t.Y[1] - t.Y[0]);
        if (Math.Abs(area) < 1e-9) return;
        int minX = Math.Max(0, (int)Math.Floor(Math.Min(t.X[0], Math.Min(t.X[1], t.X[2]))));
        int maxX = Math.Min(w - 1, (int)Math.Ceiling(Math.Max(t.X[0], Math.Max(t.X[1], t.X[2]))));
        int minY = Math.Max(0, (int)Math.Floor(Math.Min(t.Y[0], Math.Min(t.Y[1], t.Y[2]))));
        int maxY = Math.Min(w - 1, (int)Math.Ceiling(Math.Max(t.Y[0], Math.Max(t.Y[1], t.Y[2]))));
        for (int y = minY; y <= maxY; y++)
        {
            double py = y + 0.5;
            for (int x = minX; x <= maxX; x++)
            {
                double px = x + 0.5;
                double w0 = ((t.X[1] - px) * (t.Y[2] - py) - (t.X[2] - px) * (t.Y[1] - py)) / area;
                double w1 = ((t.X[2] - px) * (t.Y[0] - py) - (t.X[0] - px) * (t.Y[2] - py)) / area;
                double w2 = 1 - w0 - w1;
                if (w0 < -1e-7 || w1 < -1e-7 || w2 < -1e-7) continue;
                double d = w0 * t.D[0] + w1 * t.D[1] + w2 * t.D[2];
                int i = y * w + x;
                if (d <= depth[i]) continue;
                double light = 1.12;
                if (!t.Neon)
                {
                    double nx = w0 * t.NX[0] + w1 * t.NX[1] + w2 * t.NX[2];
                    double ny = w0 * t.NY[0] + w1 * t.NY[1] + w2 * t.NY[2];
                    double nz = w0 * t.NZ[0] + w1 * t.NZ[1] + w2 * t.NZ[2];
                    double len = Math.Sqrt(nx * nx + ny * ny + nz * nz);
                    double dot = (nx * Light[0] + ny * Light[1] + nz * Light[2]) / len;
                    light = Ambient + Diffuse * Math.Max(0, dot);
                }
                double r = t.Cr * light, g = t.Cg * light, b = t.Cb * light;
                if (light > 1)
                {
                    // brighter than the paint itself: lean towards white, like a shiny toy
                    double k = (light - 1) * 1.6;
                    r = t.Cr + (1 - t.Cr) * k; g = t.Cg + (1 - t.Cg) * k; b = t.Cb + (1 - t.Cb) * k;
                }
                if (solid)
                {
                    depth[i] = d;
                    rgba[i * 4] = (float)r; rgba[i * 4 + 1] = (float)g; rgba[i * 4 + 2] = (float)b; rgba[i * 4 + 3] = 1;
                }
                else
                {
                    float a = (float)t.Alpha;
                    rgba[i * 4] = (float)r * a + rgba[i * 4] * (1 - a);
                    rgba[i * 4 + 1] = (float)g * a + rgba[i * 4 + 1] * (1 - a);
                    rgba[i * 4 + 2] = (float)b * a + rgba[i * 4 + 2] * (1 - a);
                    rgba[i * 4 + 3] = a + rgba[i * 4 + 3] * (1 - a);
                }
                cover[i] = 1;
            }
        }
    }

    // size = picture size in pixels, fine = how many tiny samples per pixel side, fit = how much of the picture the model fills
    public static IconImage Render(IconModel model, int size, int fine, double fit)
    {
        List<IconTri> tris = Triangles(model);
        double minX = double.MaxValue, maxX = double.MinValue, minY = double.MaxValue, maxY = double.MinValue;
        foreach (IconTri t in tris)
        {
            for (int i = 0; i < 3; i++)
            {
                minX = Math.Min(minX, t.X[i]); maxX = Math.Max(maxX, t.X[i]);
                minY = Math.Min(minY, t.Y[i]); maxY = Math.Max(maxY, t.Y[i]);
            }
        }
        int w = size * fine;
        double scale = fit * w / Math.Max(maxX - minX, maxY - minY);
        double midX = (minX + maxX) / 2, midY = (minY + maxY) / 2;
        foreach (IconTri t in tris)
        {
            for (int i = 0; i < 3; i++)
            {
                t.X[i] = w / 2.0 + (t.X[i] - midX) * scale;
                t.Y[i] = w / 2.0 - (t.Y[i] - midY) * scale;
            }
        }
        double[] depth = new double[w * w];
        for (int i = 0; i < depth.Length; i++) depth[i] = double.NegativeInfinity;
        float[] rgba = new float[w * w * 4];
        byte[] cover = new byte[w * w];
        List<IconTri> glass = new List<IconTri>();
        foreach (IconTri t in tris)
        {
            if (t.Alpha >= 0.999) Fill(t, w, depth, rgba, cover, true); else glass.Add(t);
        }
        glass.Sort(delegate (IconTri a, IconTri b) { return a.Depth().CompareTo(b.Depth()); });
        foreach (IconTri t in glass) Fill(t, w, depth, rgba, cover, false);

        // shrink the fine picture down (this is what makes the edges smooth)
        IconImage image = new IconImage();
        image.Size = size;
        image.Rgba = new float[size * size * 4];
        image.Cover = new float[size * size];
        float samples = fine * fine;
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                float r = 0, g = 0, b = 0, a = 0, c = 0;
                for (int fy = 0; fy < fine; fy++)
                {
                    int row = (y * fine + fy) * w + x * fine;
                    for (int fx = 0; fx < fine; fx++)
                    {
                        int i = row + fx;
                        float pa = rgba[i * 4 + 3];
                        r += rgba[i * 4]; g += rgba[i * 4 + 1]; b += rgba[i * 4 + 2]; a += pa;
                        c += cover[i];
                    }
                }
                int o = (y * size + x) * 4;
                image.Rgba[o] = r / samples; image.Rgba[o + 1] = g / samples; image.Rgba[o + 2] = b / samples; image.Rgba[o + 3] = a / samples;
                image.Cover[y * size + x] = c / samples;
            }
        }
        return image;
    }

    // A dark ink line around the outside of the picture, like the outlines on the game's text and buttons.
    public static IconImage Outline(IconImage source, double radius, string inkHex)
    {
        int size = source.Size;
        Color ink = ColorTranslator.FromHtml("#" + inkHex);
        float ir = ink.R / 255f, ig = ink.G / 255f, ib = ink.B / 255f;
        int reach = (int)Math.Ceiling(radius + 1);
        List<int[]> offsets = new List<int[]>();
        List<float> weights = new List<float>();
        for (int dy = -reach; dy <= reach; dy++)
        {
            for (int dx = -reach; dx <= reach; dx++)
            {
                double weight = Math.Min(1, Math.Max(0, radius + 0.5 - Math.Sqrt(dx * dx + dy * dy)));
                if (weight > 0) { offsets.Add(new int[] { dx, dy }); weights.Add((float)weight); }
            }
        }
        IconImage result = new IconImage();
        result.Size = size;
        result.Rgba = new float[size * size * 4];
        result.Cover = source.Cover;
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                float spread = 0;
                for (int k = 0; k < offsets.Count; k++)
                {
                    int sx = x + offsets[k][0], sy = y + offsets[k][1];
                    if (sx < 0 || sy < 0 || sx >= size || sy >= size) continue;
                    float value = source.Cover[sy * size + sx] * weights[k];
                    if (value > spread) spread = value;
                }
                int i = y * size + x, o = i * 4;
                float inkAmount = Math.Max(0, spread - source.Cover[i]);
                result.Rgba[o] = source.Rgba[o] + ir * inkAmount;
                result.Rgba[o + 1] = source.Rgba[o + 1] + ig * inkAmount;
                result.Rgba[o + 2] = source.Rgba[o + 2] + ib * inkAmount;
                result.Rgba[o + 3] = Math.Min(1, source.Rgba[o + 3] + inkAmount);
            }
        }
        return result;
    }

    // Reads a picture drawn elsewhere (for example by Blender), trims the empty edge away and
    // centres it so its longer side fills `fit` of a size x size picture. Ready for Outline().
    public static IconImage FromFile(string path, int size, double fit)
    {
        using (Bitmap source = new Bitmap(path))
        {
            int w = source.Width, h = source.Height;
            BitmapData data = source.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            byte[] bytes = new byte[w * h * 4];
            Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
            source.UnlockBits(data);
            int minX = w, minY = h, maxX = -1, maxY = -1;
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    if (bytes[(y * w + x) * 4 + 3] > 8)
                    {
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
                }
            }
            int boxW = maxX - minX + 1, boxH = maxY - minY + 1;
            double scale = fit * size / Math.Max(boxW, boxH);
            float drawW = (float)(boxW * scale), drawH = (float)(boxH * scale);
            IconImage image = new IconImage();
            image.Size = size;
            image.Rgba = new float[size * size * 4];
            image.Cover = new float[size * size];
            using (Bitmap canvas = new Bitmap(size, size, PixelFormat.Format32bppPArgb))
            {
                using (Graphics g = Graphics.FromImage(canvas))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.Clear(Color.Transparent);
                    g.DrawImage(source, new RectangleF((size - drawW) / 2f, (size - drawH) / 2f, drawW, drawH),
                        new RectangleF(minX, minY, boxW, boxH), GraphicsUnit.Pixel);
                }
                BitmapData read = canvas.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                byte[] pixels = new byte[size * size * 4];
                Marshal.Copy(read.Scan0, pixels, 0, pixels.Length);
                canvas.UnlockBits(read);
                for (int i = 0; i < size * size; i++)
                {
                    float a = pixels[i * 4 + 3] / 255f;
                    image.Rgba[i * 4] = pixels[i * 4 + 2] / 255f;
                    image.Rgba[i * 4 + 1] = pixels[i * 4 + 1] / 255f;
                    image.Rgba[i * 4 + 2] = pixels[i * 4] / 255f;
                    image.Rgba[i * 4 + 3] = a;
                    image.Cover[i] = Math.Min(1f, a * 2.5f); // see-through wings still get an outline
                }
            }
            return image;
        }
    }

    public static Bitmap ToBitmap(IconImage image)
    {
        int size = image.Size;
        byte[] bytes = new byte[size * size * 4];
        for (int i = 0; i < size * size; i++)
        {
            float a = image.Rgba[i * 4 + 3];
            if (a <= 0.0005f) continue;
            bytes[i * 4] = Byte(image.Rgba[i * 4 + 2] / a);
            bytes[i * 4 + 1] = Byte(image.Rgba[i * 4 + 1] / a);
            bytes[i * 4 + 2] = Byte(image.Rgba[i * 4] / a);
            bytes[i * 4 + 3] = Byte(a);
        }
        Bitmap bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        BitmapData data = bitmap.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(bytes, 0, data.Scan0, bytes.Length);
        bitmap.UnlockBits(data);
        return bitmap;
    }

    static byte Byte(float value) { return (byte)Math.Max(0, Math.Min(255, Math.Round(value * 255))); }

    // One big picture with every icon on it (large and tiny), to check how they look on the game's colours.
    public static void Sheet(List<string> names, List<Bitmap> pictures, string path, int columns)
    {
        int cell = 170, rows = (pictures.Count + columns - 1) / columns;
        Color[] backs = new Color[] { Color.FromArgb(44, 40, 52), Color.FromArgb(255, 194, 26), Color.FromArgb(58, 157, 240) };
        using (Bitmap sheet = new Bitmap(columns * cell, rows * (cell + 26)))
        using (Graphics g = Graphics.FromImage(sheet))
        using (Font font = new Font("Segoe UI", 9, FontStyle.Bold))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(backs[0]);
            for (int i = 0; i < pictures.Count; i++)
            {
                int x = (i % columns) * cell, y = (i / columns) * (cell + 26);
                g.DrawImage(pictures[i], new Rectangle(x + 4, y + 4, 118, 118));
                for (int b = 0; b < backs.Length; b++)
                {
                    using (SolidBrush brush = new SolidBrush(backs[b])) g.FillRectangle(brush, x + 126, y + 4 + b * 40, 40, 38);
                    g.DrawImage(pictures[i], new Rectangle(x + 130, y + 7 + b * 40, 32, 32));
                }
                g.DrawString(names[i], font, Brushes.White, x + 4, y + 124);
            }
            sheet.Save(path, ImageFormat.Png);
        }
    }
}
