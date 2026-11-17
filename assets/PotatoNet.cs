// PotatoPC: замер скорости интернета через публичные адреса speed.cloudflare.com
// (/__down?bytes=N - скачать N байт, /__up - отправить, /cdn-cgi/trace - где сервер).
// Несколько параллельных потоков, первые ~1.5 с (разгон TCP) не считаются.
// Совместимо с C# 5 (Windows PowerShell 5.1 / .NET Framework 4.x).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Threading;

public static class PotatoNet
{
    public const string Base = "https://speed.cloudflare.com";
    public static volatile bool Cancel;
    // Текущая скорость (Мбит/с) и фаза - читаются из UI во время замера.
    public static double Live;
    public static string Phase = "";

    static long _bytes;
    static volatile bool _stop;

    static void Prepare()
    {
        ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
        if (ServicePointManager.DefaultConnectionLimit < 32) ServicePointManager.DefaultConnectionLimit = 32;
        ServicePointManager.Expect100Continue = false;
    }

    static HttpWebRequest NewRequest(string url, string method)
    {
        var r = (HttpWebRequest)WebRequest.Create(url);
        r.Method = method;
        r.UserAgent = "PotatoPC speedtest";
        r.Timeout = 15000;
        r.ReadWriteTimeout = 15000;
        r.KeepAlive = true;
        r.Proxy = WebRequest.DefaultWebProxy;
        return r;
    }

    // Строки вида "colo=DME" из /cdn-cgi/trace.
    public static Dictionary<string, string> Trace()
    {
        Prepare();
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var r = NewRequest(Base + "/cdn-cgi/trace", "GET");
        using (var resp = (HttpWebResponse)r.GetResponse())
        using (var sr = new StreamReader(resp.GetResponseStream()))
        {
            string line;
            while ((line = sr.ReadLine()) != null)
            {
                int i = line.IndexOf('=');
                if (i > 0) d[line.Substring(0, i)] = line.Substring(i + 1);
            }
        }
        return d;
    }

    // Задержка до сервера: n запросов без данных. Возвращает время каждого в мс (-1 = ошибка).
    public static double[] Latency(int n)
    {
        Prepare();
        Phase = "latency";
        var res = new double[n];
        // первый запрос открывает соединение (TLS) - не считаем
        try { Ping(); } catch { }
        for (int i = 0; i < n && !Cancel; i++)
        {
            try { res[i] = Ping(); } catch { res[i] = -1; }
        }
        return res;
    }

    static double Ping()
    {
        var sw = Stopwatch.StartNew();
        var r = NewRequest(Base + "/__down?bytes=0", "GET");
        using (var resp = (HttpWebResponse)r.GetResponse())
        {
            sw.Stop();
            using (var s = resp.GetResponseStream()) { s.ReadByte(); }
        }
        return sw.Elapsed.TotalMilliseconds;
    }

    // Скачивание: streams потоков в течение seconds секунд. Возвращает Мбит/с.
    public static double Download(int streams, int seconds)
    {
        Prepare();
        Phase = "down";
        return Run(streams, seconds, true);
    }

    // Отдача. Возвращает Мбит/с.
    public static double Upload(int streams, int seconds)
    {
        Prepare();
        Phase = "up";
        return Run(streams, seconds, false);
    }

    static double Run(int streams, int seconds, bool down)
    {
        _bytes = 0; _stop = false; Live = 0;
        var threads = new List<Thread>();
        for (int i = 0; i < streams; i++)
        {
            var t = new Thread(down ? (ThreadStart)DownWorker : (ThreadStart)UpWorker);
            t.IsBackground = true;
            threads.Add(t);
            t.Start();
        }
        var sw = Stopwatch.StartNew();
        double warm = 1.5;
        long startBytes = 0;
        bool counting = false;
        double startAt = 0;
        long lastBytes = 0; double lastT = 0;
        while (sw.Elapsed.TotalSeconds < seconds + warm && !Cancel)
        {
            Thread.Sleep(200);
            double t = sw.Elapsed.TotalSeconds;
            long b = Interlocked.Read(ref _bytes);
            if (!counting && t >= warm) { counting = true; startBytes = b; startAt = t; }
            // скользящая скорость за последние ~0.2 с, сглаженная
            double inst = (t - lastT) > 0 ? (b - lastBytes) * 8.0 / 1e6 / (t - lastT) : 0;
            Live = Live <= 0 ? inst : Live * 0.7 + inst * 0.3;
            lastBytes = b; lastT = t;
        }
        _stop = true;
        double total = sw.Elapsed.TotalSeconds;
        long end = Interlocked.Read(ref _bytes);
        foreach (var th in threads) { th.Join(3000); }
        if (!counting || total - startAt <= 0.1) return 0;
        double mbps = (end - startBytes) * 8.0 / 1e6 / (total - startAt);
        Live = mbps;
        return mbps;
    }

    static void DownWorker()
    {
        var buf = new byte[65536];
        while (!_stop && !Cancel)
        {
            try
            {
                var r = NewRequest(Base + "/__down?bytes=25000000", "GET");
                using (var resp = (HttpWebResponse)r.GetResponse())
                using (var s = resp.GetResponseStream())
                {
                    int n;
                    while (!_stop && !Cancel && (n = s.Read(buf, 0, buf.Length)) > 0)
                        Interlocked.Add(ref _bytes, n);
                    if (_stop || Cancel) r.Abort();
                }
            }
            catch { if (!_stop && !Cancel) Thread.Sleep(300); }
        }
    }

    static void UpWorker()
    {
        var buf = new byte[65536];
        new Random().NextBytes(buf);
        const int size = 4000000;
        while (!_stop && !Cancel)
        {
            long counted = 0;
            try
            {
                var r = NewRequest(Base + "/__up", "POST");
                r.ContentType = "application/octet-stream";
                r.ContentLength = size;
                r.AllowWriteStreamBuffering = false;
                using (var s = r.GetRequestStream())
                {
                    int sent = 0;
                    while (sent < size && !_stop && !Cancel)
                    {
                        int n = Math.Min(buf.Length, size - sent);
                        s.Write(buf, 0, n);
                        sent += n;
                        counted += n;
                        Interlocked.Add(ref _bytes, n);
                    }
                    if (_stop || Cancel) { r.Abort(); break; }
                }
                using (var resp = r.GetResponse()) { }
            }
            catch
            {
                // отправка оборвалась до ответа сервера - эти байты не засчитываем
                if (!_stop && !Cancel) { Interlocked.Add(ref _bytes, -counted); Thread.Sleep(300); }
            }
        }
    }
}
