using System;
using System.Diagnostics;
using System.Globalization;

namespace SDAM_Rangefinder.Tests
{
    /// <summary>
    /// Protocol.cs / LinkStats.cs 的控制台单元测试（不依赖 WinForms/串口）。
    /// 用 in-box csc.exe 编译：tests\run_tests.bat。
    /// </summary>
    internal static class ProtocolTests
    {
        private static int _passed;
        private static int _failed;

        private static int Main()
        {
            Console.WriteLine("SDAM host protocol tests");
            Console.WriteLine("-----------------------");

            TestRealLine();
            TestReorderedLine();
            TestOptionalFields();
            TestUnknownKeys();
            TestInvalidDistance();
            TestLowercase();
            TestBadInput();
            TestWhitespace();
            TestLineAssembler();
            TestGarbageRecovery();
            TestOverflow();
            TestBaudIndex();
            TestLinkStatsNormal();
            TestLinkStatsByteFrameMismatch();
            TestLinkStatsWrap();
            TestLinkStatsReset();
            TestSessionStats();

            Console.WriteLine("-----------------------");
            Console.WriteLine(string.Format(CultureInfo.InvariantCulture,
                "passed: {0}  failed: {1}", _passed, _failed));
            return _failed == 0 ? 0 : 1;
        }

        // ------------------------------------------------------------------
        // 解析器
        // ------------------------------------------------------------------

        private static void TestRealLine()
        {
            TofSample s;
            string err;
            bool ok = TofLineParser.TryParse(
                "D=0843 I=0924 A=0012 C=00 F=0000 U=3 B=0000 L=1\r\n",
                new DateTime(2026, 11, 6, 21, 0, 0), 12345, out s, out err);

            Check(ok, "real line parses");
            Check(err == null, "real line has no error");
            Check(s != null && s.Distance == 0x0843, "real line D=2115");
            Check(s != null && s.Intensity == 0x0924, "real line I=2340");
            Check(s != null && s.Ambient == 0x0012, "real line A=18");
            Check(s != null && s.CrcErrors == 0, "real line C=0");
            Check(s != null && s.FrameCount == 0, "real line F=0");
            Check(s != null && s.BaudIndex == 3, "real line U=3");
            Check(s != null && s.RxBytes == 0, "real line B=0");
            Check(s != null && s.LinkOk == 1, "real line L=1");
            Check(s != null && s.HasD && s.HasI && s.HasA && s.HasC && s.HasF && s.HasU && s.HasB && s.HasL,
                "real line all fields present");
            Check(s != null && s.DistanceValid, "real line distance valid");
            Check(s != null && s.RawLine == "D=0843 I=0924 A=0012 C=00 F=0000 U=3 B=0000 L=1",
                "real line raw text kept");
        }

        private static void TestReorderedLine()
        {
            TofSample s;
            string err;
            bool ok = TofLineParser.TryParse(
                "L=1 U=2 B=0102 F=00A0 C=03 A=0005 I=0010 D=02BC",
                DateTime.Now, 1, out s, out err);

            Check(ok, "reordered line parses");
            Check(s != null && s.Distance == 0x02BC, "reordered line D");
            Check(s != null && s.BaudIndex == 2, "reordered line U");
            Check(s != null && s.RxBytes == 0x0102, "reordered line B");
        }

        private static void TestOptionalFields()
        {
            TofSample s;
            string err;
            bool ok = TofLineParser.TryParse("D=0100 I=0001 A=0000 C=00 U=1", DateTime.Now, 1, out s, out err);

            Check(ok, "optional fields line parses");
            Check(s != null && !s.HasF && !s.HasB && !s.HasL, "optional fields absent");
            Check(s != null && s.FrameCount == TofSample.Missing && s.RxBytes == TofSample.Missing,
                "optional fields default to Missing");
            Check(s != null && s.DistanceValid, "missing L treated as unknown (valid)");
        }

        private static void TestUnknownKeys()
        {
            TofSample s;
            string err;
            bool ok = TofLineParser.TryParse("D=0100 X=ZZZ KEY=VALUE T=1", DateTime.Now, 1, out s, out err);

            Check(ok, "unknown keys ignored");
            Check(s != null && s.Distance == 0x0100, "unknown keys keep D");
        }

        private static void TestInvalidDistance()
        {
            Check(!Parse("D=0000 L=1").DistanceValid, "D=0000 invalid");
            Check(!Parse("D=FFFF L=1").DistanceValid, "D=FFFF invalid");
            Check(!Parse("D=8000 L=1").DistanceValid, "D=8000 invalid (bit15 set)");
            Check(!Parse("D=0100 L=0").DistanceValid, "L=0 invalid");
            Check(Parse("D=7FFF L=1").DistanceValid, "D=7FFF valid");
        }

        private static void TestLowercase()
        {
            TofSample s;
            string err;
            bool ok = TofLineParser.TryParse("d=0abc i=00ff a=0000 c=0 u=1 b=0000 f=0000 l=1",
                DateTime.Now, 1, out s, out err);

            Check(ok, "lowercase keys parse");
            Check(s != null && s.Distance == 0x0ABC, "lowercase hex value");
            Check(s != null && s.Intensity == 0x00FF, "lowercase field key");
        }

        private static void TestBadInput()
        {
            TofSample s;
            string err;

            Check(!TofLineParser.TryParse(null, DateTime.Now, 1, out s, out err), "null line rejected");
            Check(!TofLineParser.TryParse("   ", DateTime.Now, 1, out s, out err), "blank line rejected");
            Check(!TofLineParser.TryParse("I=0001 L=1", DateTime.Now, 1, out s, out err), "missing D rejected");
            Check(TofLineParser.TryParse("I=0001", DateTime.Now, 1, out s, out err) == false,
                "line without D rejected again");
            Check(!TofLineParser.TryParse("D=GGGG", DateTime.Now, 1, out s, out err), "bad hex rejected");
            Check(!TofLineParser.TryParse("D=", DateTime.Now, 1, out s, out err), "empty field rejected");
            Check(!TofLineParser.TryParse("D=12345", DateTime.Now, 1, out s, out err), "too many hex digits rejected");
            Check(!TofLineParser.TryParse("D=0100 U=99", DateTime.Now, 1, out s, out err), "two-digit U rejected");
            Check(!TofLineParser.TryParse("D=0100 U=A", DateTime.Now, 1, out s, out err), "non-decimal U rejected");
        }

        private static void TestWhitespace()
        {
            TofSample s;
            string err;
            bool ok = TofLineParser.TryParse("   D=0100\tI=0001   L=1  ", DateTime.Now, 1, out s, out err);
            Check(ok, "extra whitespace tolerated");
            Check(s != null && s.Distance == 0x0100, "extra whitespace keeps D");
        }

        // ------------------------------------------------------------------
        // 行装配器
        // ------------------------------------------------------------------

        private static void TestLineAssembler()
        {
            LineAssembler assembler = new LineAssembler();
            string text = "D=0100 L=1\r\n";
            string line = null;
            int lines = 0;
            for (int i = 0; i < text.Length; i++)
            {
                string produced;
                if (assembler.Feed(text[i], out produced))
                {
                    lines++;
                    line = produced;
                }
            }

            Check(lines == 1, "assembler produces one line");
            Check(line == "D=0100 L=1", "assembler trims CR");

            string second;
            assembler.Feed('D', out second);
            Check(second == null, "assembler partial line not emitted");
        }

        private static void TestGarbageRecovery()
        {
            LineAssembler assembler = new LineAssembler();
            string ignored;
            assembler.Feed((char)0, out ignored);
            assembler.Feed((char)0, out ignored);

            string text = "D=0100 L=1\r\n";
            string line = null;
            for (int i = 0; i < text.Length; i++)
            {
                string produced;
                if (assembler.Feed(text[i], out produced))
                {
                    line = produced;
                }
            }

            Check(line == "D=0100 L=1", "valid line recovered after 0x00 bytes");
            Check(assembler.DiscardedBytes >= 2, "garbage bytes counted");
        }

        private static void TestOverflow()
        {
            LineAssembler assembler = new LineAssembler();
            string ignored;
            for (int i = 0; i < LineAssembler.MaxLineLength + 10; i++)
            {
                assembler.Feed('A', out ignored);
            }
            assembler.Feed('\n', out ignored);

            Check(assembler.OverflowCount >= 1, "overlong line counted as overflow");

            string text = "D=0100 L=1\r\n";
            string line = null;
            for (int i = 0; i < text.Length; i++)
            {
                string produced;
                if (assembler.Feed(text[i], out produced))
                {
                    line = produced;
                }
            }
            Check(line == "D=0100 L=1", "assembler recovers after overflow");
        }

        // ------------------------------------------------------------------
        // LinkStats
        // ------------------------------------------------------------------

        private static void TestBaudIndex()
        {
            Check(LinkStats.BaudRateFromIndex(0) == 9600, "U=0 -> 9600");
            Check(LinkStats.BaudRateFromIndex(1) == 115200, "U=1 -> 115200");
            Check(LinkStats.BaudRateFromIndex(2) == 230400, "U=2 -> 230400");
            Check(LinkStats.BaudRateFromIndex(3) == 921600, "U=3 -> 921600");
            Check(LinkStats.BaudRateFromIndex(4) == -1, "U=4 unknown");
            Check(LinkStats.BaudRateFromIndex(-1) == -1, "U=-1 unknown");
        }

        private static void TestLinkStatsNormal()
        {
            LinkStats stats = new LinkStats();
            for (int n = 0; n <= 12; n++)
            {
                int f = 1000 + n * 10;
                int b = (23 * f) & 0xFFFF;
                stats.Update(Sample(0x0430, 100, 1, 0, f, 1, b, 1, Ts(n * 0.1)));
            }

            Check(stats.Valid, "link stats valid after 1.2 s");
            Check(Math.Abs(stats.TofFps - 100.0) < 0.01, "link stats fps=100");
            Check(Math.Abs(stats.LineRateHz - 10.0) < 0.01, "link stats line rate=10 Hz");
            Check(Math.Abs(stats.BytesPerSec - 2300.0) < 1.0, "link stats B/s=2300");
            Check(Math.Abs(stats.CrcErrPerSec) < 0.001, "link stats CRC=0");
            Check(!stats.ByteFrameMismatch, "link stats B=23F consistent");
        }

        private static void TestLinkStatsByteFrameMismatch()
        {
            LinkStats stats = new LinkStats();
            for (int n = 0; n <= 12; n++)
            {
                int f = 2000 + n * 10;
                // 每行多出 2 B 的累计误差：ΔB = 23×ΔF + 20×Δn，必然超出容差。
                int b = (23 * f + n * 20) & 0xFFFF;
                stats.Update(Sample(0x0430, 100, 1, 0, f, 1, b, 1, Ts(n * 0.1)));
            }

            Check(stats.Valid, "mismatch stats valid");
            Check(stats.ByteFrameMismatch, "link stats detects B != 23F (+100)");
        }

        private static void TestLinkStatsWrap()
        {
            LinkStats stats = new LinkStats();
            for (int n = 0; n <= 12; n++)
            {
                int f = (65500 + n * 10) & 0xFFFF;
                int b = (23 * f) & 0xFFFF;
                stats.Update(Sample(0x0430, 100, 1, 0, f, 1, b, 1, Ts(n * 0.1)));
            }

            Check(stats.Valid, "wrap stats valid");
            Check(Math.Abs(stats.TofFps - 100.0) < 0.01, "F wrap handled (fps=100)");
            Check(!stats.ConsumeBoardReset(), "F wrap is not a board reset");
        }

        private static void TestLinkStatsReset()
        {
            LinkStats stats = new LinkStats();
            for (int n = 0; n <= 4; n++)
            {
                stats.Update(Sample(0x0430, 100, 1, 0, 500 + n * 10, 1, 0, 1, Ts(n * 0.1)));
            }

            stats.Update(Sample(0x0430, 100, 1, 0, 5000, 1, 0, 1, Ts(0.5)));
            Check(stats.ConsumeBoardReset(), "F jump > 1000 detected as reset");
            Check(!stats.Valid, "reset clears stats window");
            Check(Math.Abs(stats.TofFps) < 0.001, "reset zeroes fps");

            for (int n = 1; n <= 12; n++)
            {
                stats.Update(Sample(0x0430, 100, 1, 0, 5000 + n * 10, 1, 0, 1, Ts(0.5 + n * 0.1)));
            }
            Check(stats.Valid, "stats recover after reset");
        }

        private static void TestSessionStats()
        {
            SessionStats stats = new SessionStats();
            int[] values = new int[] { 1, 2, 3, 4, 5 };
            for (int i = 0; i < values.Length; i++)
            {
                stats.Add(values[i]);
            }

            Check(stats.Count == 5, "session stats count=5");
            Check(Math.Abs(stats.Mean - 3.0) < 1e-9, "session stats mean=3");
            Check(Math.Abs(stats.StdDev - Math.Sqrt(2.0)) < 1e-9, "session stats population sigma");
            Check(stats.Min == 1, "session stats min=1");
            Check(stats.Max == 5, "session stats max=5");

            stats.Reset();
            Check(stats.Count == 0, "session stats reset");
            Check(Math.Abs(stats.Mean) < 1e-12, "session stats mean reset");
        }

        // ------------------------------------------------------------------
        // 工具
        // ------------------------------------------------------------------

        private static TofSample Parse(string line)
        {
            TofSample s;
            string err;
            if (!TofLineParser.TryParse(line, DateTime.Now, 1, out s, out err))
            {
                throw new InvalidOperationException("unexpected parse failure: " + line + " / " + err);
            }
            return s;
        }

        private static long Ts(double seconds)
        {
            return (long)(seconds * Stopwatch.Frequency);
        }

        private static TofSample Sample(int distance, int intensity, int ambient, int crc,
            int frames, int baudIndex, int rxBytes, int link, long timestamp)
        {
            TofSample s = new TofSample();
            s.ReceivedAt = DateTime.Now;
            s.Timestamp = timestamp;
            s.RawLine = "SYNTHETIC";
            s.Distance = distance;
            s.Intensity = intensity;
            s.Ambient = ambient;
            s.CrcErrors = crc;
            s.FrameCount = frames;
            s.BaudIndex = baudIndex;
            s.RxBytes = rxBytes;
            s.LinkOk = link;
            s.HasD = true;
            s.HasI = true;
            s.HasA = true;
            s.HasC = true;
            s.HasF = true;
            s.HasU = true;
            s.HasB = true;
            s.HasL = true;
            return s;
        }

        private static void Check(bool condition, string name)
        {
            if (condition)
            {
                _passed++;
                Console.WriteLine("PASS  " + name);
            }
            else
            {
                _failed++;
                Console.WriteLine("FAIL  " + name);
            }
        }
    }
}
