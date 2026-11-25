// PotatoPC: обход диска для «Что занимает место» (дерево папок с размерами).
// FindFirstFileEx с FindExInfoBasic + LARGE_FETCH - заметно быстрее DirectoryInfo.
// Точки соединения (junction, symlink) не обходятся - иначе папки посчитаются дважды.
// В каждой папке хранятся все подпапки, но только самые большие файлы (KeepFiles),
// остальные сводятся в одну строку - так дерево на 500 000 файлов занимает немного памяти.
// Совместимо с C# 5 (Windows PowerShell 5.1 / .NET Framework 4.x).
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

public class PotatoDiskNode
{
    public string Name;
    public string Path;
    public long Size;
    public long Files;
    public bool IsDir;
    public bool IsRest;      // строка «ещё N файлов»
    public bool Denied;      // нет доступа к содержимому
    public List<PotatoDiskNode> Kids;
}

public static class PotatoDisk
{
    public static volatile bool Cancel;
    public static long FilesSeen;
    public static long BytesSeen;
    public static int Threads = 4;   // верхние уровни обходятся параллельно - на SSD в разы быстрее
    public static string Current = "";
    public const int KeepFiles = 40;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WIN32_FIND_DATA
    {
        public uint dwFileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftCreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftLastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftLastWriteTime;
        public uint nFileSizeHigh;
        public uint nFileSizeLow;
        public uint dwReserved0;
        public uint dwReserved1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string cFileName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string cAlternateFileName;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr FindFirstFileExW(string lpFileName, int fInfoLevelId, out WIN32_FIND_DATA lpFindFileData, int fSearchOp, IntPtr lpSearchFilter, int dwAdditionalFlags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool FindNextFileW(IntPtr hFindFile, out WIN32_FIND_DATA lpFindFileData);

    [DllImport("kernel32.dll")]
    static extern bool FindClose(IntPtr hFindFile);

    static readonly IntPtr Invalid = new IntPtr(-1);
    const uint ATTR_DIR = 0x10;
    const uint ATTR_REPARSE = 0x400;

    public static PotatoDiskNode Scan(string root)
    {
        Cancel = false; FilesSeen = 0; BytesSeen = 0; Current = root;
        string path = root.TrimEnd('\\');
        if (path.Length == 2 && path[1] == ':') path += "\\";
        var node = new PotatoDiskNode { Name = path, Path = path, IsDir = true };
        Walk(node, 0);
        return node;
    }

    static string LongPath(string p)
    {
        if (p.StartsWith("\\\\?\\")) return p;
        if (p.StartsWith("\\\\")) return "\\\\?\\UNC\\" + p.Substring(2);
        return "\\\\?\\" + p;
    }

    static void Walk(PotatoDiskNode dir, int depth)
    {
        var kids = new List<PotatoDiskNode>();
        var files = new List<PotatoDiskNode>();
        WIN32_FIND_DATA fd;
        string search = LongPath(dir.Path.EndsWith("\\") ? dir.Path + "*" : dir.Path + "\\*");
        // 1 = FindExInfoBasic, 2 = FIND_FIRST_EX_LARGE_FETCH
        IntPtr h = FindFirstFileExW(search, 1, out fd, 0, IntPtr.Zero, 2);
        if (h == Invalid) { dir.Denied = true; dir.Kids = kids; return; }
        try
        {
            do
            {
                if (Cancel) break;
                string name = fd.cFileName;
                if (name == "." || name == "..") continue;
                string full = dir.Path.EndsWith("\\") ? dir.Path + name : dir.Path + "\\" + name;
                if ((fd.dwFileAttributes & ATTR_DIR) != 0)
                {
                    if ((fd.dwFileAttributes & ATTR_REPARSE) != 0) continue;
                    kids.Add(new PotatoDiskNode { Name = name, Path = full, IsDir = true });
                }
                else
                {
                    long size = ((long)fd.nFileSizeHigh << 32) | fd.nFileSizeLow;
                    files.Add(new PotatoDiskNode { Name = name, Path = full, Size = size, Files = 1 });
                    Interlocked.Increment(ref FilesSeen);
                    Interlocked.Add(ref BytesSeen, size);
                }
            } while (FindNextFileW(h, out fd));
        }
        finally { FindClose(h); }

        long total = 0, count = 0;
        if (depth < 3 && Threads > 1 && kids.Count > 1)
        {
            var opt = new ParallelOptions { MaxDegreeOfParallelism = Threads };
            Parallel.ForEach(kids, opt, k => { if (!Cancel) { Current = k.Path; Walk(k, depth + 1); } });
        }
        else
        {
            foreach (var k in kids)
            {
                if (Cancel) break;
                Current = k.Path;
                Walk(k, depth + 1);
            }
        }
        foreach (var k in kids) { total += k.Size; count += k.Files; }
        foreach (var f in files) { total += f.Size; count++; }

        if (files.Count > KeepFiles)
        {
            files.Sort((a, b) => b.Size.CompareTo(a.Size));
            long restSize = 0; int restCount = files.Count - KeepFiles;
            for (int i = KeepFiles; i < files.Count; i++) restSize += files[i].Size;
            files.RemoveRange(KeepFiles, files.Count - KeepFiles);
            files.Add(new PotatoDiskNode { Name = "Ещё " + restCount + " мелких файлов", Path = dir.Path, Size = restSize, Files = restCount, IsRest = true });
        }
        kids.AddRange(files);
        kids.Sort((a, b) => b.Size.CompareTo(a.Size));
        dir.Kids = kids;
        dir.Size = total;
        dir.Files = count;
    }
}
