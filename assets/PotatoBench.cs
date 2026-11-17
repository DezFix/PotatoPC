// PotatoPC: синтетические тесты для страницы «Тест ПК».
// Компилируется через Add-Type в Windows PowerShell 5.1 (компилятор C# 5):
// без интерполяции строк, ?. и прочего из C# 6+.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public static class PotatoBench
{
    public static volatile bool Cancel;

    // Смешанная целочисленная/вещественная нагрузка с обращениями к памяти (L1).
    static long Work(long n)
    {
        ulong x = 88172645463325252UL;
        double acc = 0;
        long hits = 0;
        int[] arr = new int[4096];
        for (long i = 0; i < n; i++)
        {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17;
            int k = (int)(x & 4095);
            arr[k] += (int)i;
            acc += Math.Sqrt((double)(x & 0xFFFF));
            if ((arr[k] & 1) == 0) hits++;
        }
        return hits + (long)acc;
    }

    const long Chunk = 250000;

    // Итераций в секунду на одном потоке.
    public static double CpuSingle(int ms)
    {
        long total = 0, sink = 0;
        Stopwatch sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < ms && !Cancel) { sink += Work(Chunk); total += Chunk; }
        GC.KeepAlive(sink);
        return total / sw.Elapsed.TotalSeconds;
    }

    // Нагрузка на все потоки. Возвращает пропускную способность по секундам
    // (итераций/с за каждую секунду) - по ней видно снижение частоты от нагрева.
    public static double[] CpuMultiSamples(int seconds, int threads)
    {
        long counter = 0;
        bool stop = false;
        Thread[] ts = new Thread[threads];
        for (int t = 0; t < threads; t++)
        {
            ts[t] = new Thread(delegate ()
            {
                long sink = 0;
                while (!Volatile.Read(ref stop) && !Cancel) { sink += Work(Chunk); Interlocked.Add(ref counter, Chunk); }
                GC.KeepAlive(sink);
            });
            ts[t].IsBackground = true;
            ts[t].Priority = ThreadPriority.BelowNormal;
            ts[t].Start();
        }
        double[] samples = new double[seconds];
        long last = 0;
        Stopwatch sw = Stopwatch.StartNew();
        double lastT = 0;
        for (int s = 0; s < seconds && !Cancel; s++)
        {
            Thread.Sleep(1000);
            long now = Interlocked.Read(ref counter);
            double t = sw.Elapsed.TotalSeconds;
            samples[s] = (now - last) / Math.Max(0.001, t - lastT);
            last = now; lastT = t;
        }
        Volatile.Write(ref stop, true);
        foreach (Thread th in ts) th.Join(5000);
        return samples;
    }

    // Скорость копирования памяти, МБ/с (блоки больше кэша процессора).
    public static double MemCopy(int mb, int ms)
    {
        byte[] a = new byte[mb * 1048576];
        byte[] b = new byte[mb * 1048576];
        new Random(1).NextBytes(a);
        long copies = 0;
        Stopwatch sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < ms && !Cancel) { Buffer.BlockCopy(a, 0, b, 0, a.Length); copies++; }
        return (copies * (double)mb) / sw.Elapsed.TotalSeconds;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(IntPtr h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadFile(IntPtr h, IntPtr buf, uint n, out uint done, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetFilePointerEx(IntPtr h, long dist, out long newPos, uint method);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr size, uint type, uint protect);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool VirtualFree(IntPtr a, UIntPtr size, uint type);

    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
    const uint CREATE_ALWAYS = 2, OPEN_EXISTING = 3;
    const uint NO_BUFFERING = 0x20000000, WRITE_THROUGH = 0x80000000;
    const int Block = 1048576;

    static IntPtr Open(string path, bool create)
    {
        IntPtr h = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, 0, IntPtr.Zero, create ? CREATE_ALWAYS : OPEN_EXISTING, NO_BUFFERING | WRITE_THROUGH, IntPtr.Zero);
        if (h == new IntPtr(-1)) throw new IOException("CreateFile: " + Marshal.GetLastWin32Error());
        return h;
    }

    // Диск без кэша Windows: [запись МБ/с, чтение МБ/с, случайное чтение 4К МБ/с, IOPS 4К].
    public static double[] Disk(string path, int sizeMb, int randMs)
    {
        double[] r = new double[4];
        IntPtr buf = VirtualAlloc(IntPtr.Zero, new UIntPtr((uint)Block), 0x3000, 4);
        if (buf == IntPtr.Zero) throw new OutOfMemoryException();
        try
        {
            byte[] rnd = new byte[Block];
            new Random(7).NextBytes(rnd);   // несжимаемые данные
            Marshal.Copy(rnd, 0, buf, Block);
            uint done;
            IntPtr h = Open(path, true);
            Stopwatch sw = Stopwatch.StartNew();
            try
            {
                for (int i = 0; i < sizeMb && !Cancel; i++)
                    if (!WriteFile(h, buf, (uint)Block, out done, IntPtr.Zero)) throw new IOException("WriteFile: " + Marshal.GetLastWin32Error());
            }
            finally { CloseHandle(h); }
            r[0] = sizeMb / sw.Elapsed.TotalSeconds;

            h = Open(path, false);
            try
            {
                sw = Stopwatch.StartNew();
                for (int i = 0; i < sizeMb && !Cancel; i++)
                    if (!ReadFile(h, buf, (uint)Block, out done, IntPtr.Zero)) throw new IOException("ReadFile: " + Marshal.GetLastWin32Error());
                r[1] = sizeMb / sw.Elapsed.TotalSeconds;

                Random rng = new Random(11);
                int pages = sizeMb * 256;
                long ops = 0, pos;
                sw = Stopwatch.StartNew();
                while (sw.ElapsedMilliseconds < randMs && !Cancel)
                {
                    long off = (long)rng.Next(0, pages) * 4096;
                    SetFilePointerEx(h, off, out pos, 0);
                    if (!ReadFile(h, buf, 4096, out done, IntPtr.Zero)) throw new IOException("ReadFile 4K: " + Marshal.GetLastWin32Error());
                    ops++;
                }
                double sec = sw.Elapsed.TotalSeconds;
                r[3] = ops / sec;
                r[2] = r[3] * 4096 / 1048576.0;
            }
            finally { CloseHandle(h); }
        }
        finally
        {
            VirtualFree(buf, UIntPtr.Zero, 0x8000);
            try { File.Delete(path); } catch { }
        }
        return r;
    }
}
