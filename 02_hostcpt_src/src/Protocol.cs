using System;
using System.Globalization;
using System.Text;

namespace SDAM_Rangefinder
{
    /// <summary>
    /// 一帧 FPGA 上行文本行的解析结果。
    /// 协议（V2.0，见 top_tof.v）：
    ///   D=hhhh I=hhhh A=hhhh C=hh F=hhhh U=d B=hhhh L=d\r\n
    /// D=主目标距离(mm) I=强度 A=环境光 C=CRC错计数(低8位) F=合法帧计数
    /// U=PC上行波特率档(0..3) B=累计收字节(低16位) L=链路状态(1=1.398s内收到过合法帧)
    /// 所有 h 为大写十六进制；U/L 为十进制。
    /// 设计原则：字段可增删、可乱序、可缺失，解析器只依赖 "键=值" 与空格分隔，
    /// 这样 FPGA 端因资源紧张增删字段时上位机不会整体失效。
    /// </summary>
    public sealed class TofSample
    {
        /// <summary>字段缺失时的占位值。</summary>
        public const int Missing = -1;

        public DateTime ReceivedAt;
        /// <summary>Stopwatch.GetTimestamp()，用于高精度计算行间隔。</summary>
        public long Timestamp;
        /// <summary>去掉行尾 CR/LF 后的原始文本，便于 CSV 留档。</summary>
        public string RawLine;

        public bool HasD;
        public bool HasI;
        public bool HasA;
        public bool HasC;
        public bool HasF;
        public bool HasU;
        public bool HasB;
        public bool HasL;

        /// <summary>主目标距离，单位 mm（FPGA 原始值）。</summary>
        public int Distance = Missing;
        /// <summary>主目标强度（16 位原始码值，不是物理单位）。</summary>
        public int Intensity = Missing;
        /// <summary>环境光/阳光基底（16 位原始码值）。</summary>
        public int Ambient = Missing;
        /// <summary>CRC 错误计数（只有低 8 位，会回绕）。</summary>
        public int CrcErrors = Missing;
        /// <summary>合法帧计数（16 位，会回绕）。</summary>
        public int FrameCount = Missing;
        /// <summary>下位机 PC 上行波特率档：0=9600 1=115200 2=230400 3=921600。</summary>
        public int BaudIndex = Missing;
        /// <summary>FPGA 累计收到的字节数（低 16 位，会回绕）。</summary>
        public int RxBytes = Missing;
        /// <summary>链路状态：1=正常，0=超时；缺失时为 Missing。</summary>
        public int LinkOk = Missing;

        /// <summary>
        /// 距离是否可用于显示/统计。
        /// 与 tof1_parser.v 的 dist_valid 判据一致：非 0、非 0xFFFF、最高位为 0，
        /// 且本行链路未报断（L=0 时不采信距离）。
        /// </summary>
        public bool DistanceValid
        {
            get
            {
                return HasD
                    && LinkOk != 0
                    && Distance != 0
                    && Distance != 0xFFFF
                    && Distance < 0x8000;
            }
        }

        public override string ToString()
        {
            return RawLine == null ? string.Empty : RawLine;
        }
    }

    /// <summary>
    /// 文本行协议解析器。只做字符串处理，不依赖串口/WinForms，便于单元测试。
    /// </summary>
    public static class TofLineParser
    {
        /// <summary>
        /// 解析一行（可带行尾 \r\n，也可不带）。
        /// </summary>
        /// <param name="line">待解析文本。</param>
        /// <param name="receivedAt">本地接收时间。</param>
        /// <param name="timestamp">Stopwatch.GetTimestamp()。</param>
        /// <param name="sample">成功时的解析结果。</param>
        /// <param name="error">失败原因（中文，可直接写日志）。</param>
        public static bool TryParse(string line, DateTime receivedAt, long timestamp,
            out TofSample sample, out string error)
        {
            sample = null;
            error = null;

            if (line == null)
            {
                error = "数据行为空";
                return false;
            }

            string text = line.Trim();
            if (text.Length == 0)
            {
                error = "数据行为空";
                return false;
            }

            string[] tokens = text.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            TofSample s = new TofSample();
            s.ReceivedAt = receivedAt;
            s.Timestamp = timestamp;
            s.RawLine = text;

            for (int i = 0; i < tokens.Length; i++)
            {
                string token = tokens[i];
                int eq = token.IndexOf('=');
                if (eq <= 0 || eq == token.Length - 1)
                {
                    error = string.Format(CultureInfo.InvariantCulture, "字段格式错误: {0}", token);
                    return false;
                }
                if (eq != 1)
                {
                    // 多字符键不是本协议字段，忽略（前向兼容）。
                    continue;
                }

                char key = char.ToUpperInvariant(token[0]);
                string value = token.Substring(2);
                int parsed;

                switch (key)
                {
                    case 'D':
                        if (!TryParseHex(value, 4, out parsed))
                        {
                            error = string.Format(CultureInfo.InvariantCulture, "字段 D 格式错误: {0}", value);
                            return false;
                        }
                        s.Distance = parsed;
                        s.HasD = true;
                        break;

                    case 'I':
                        if (!TryParseHex(value, 4, out parsed))
                        {
                            error = string.Format(CultureInfo.InvariantCulture, "字段 I 格式错误: {0}", value);
                            return false;
                        }
                        s.Intensity = parsed;
                        s.HasI = true;
                        break;

                    case 'A':
                        if (!TryParseHex(value, 4, out parsed))
                        {
                            error = string.Format(CultureInfo.InvariantCulture, "字段 A 格式错误: {0}", value);
                            return false;
                        }
                        s.Ambient = parsed;
                        s.HasA = true;
                        break;

                    case 'C':
                        if (!TryParseHex(value, 2, out parsed))
                        {
                            error = string.Format(CultureInfo.InvariantCulture, "字段 C 格式错误: {0}", value);
                            return false;
                        }
                        s.CrcErrors = parsed;
                        s.HasC = true;
                        break;

                    case 'F':
                        if (!TryParseHex(value, 4, out parsed))
                        {
                            error = string.Format(CultureInfo.InvariantCulture, "字段 F 格式错误: {0}", value);
                            return false;
                        }
                        s.FrameCount = parsed;
                        s.HasF = true;
                        break;

                    case 'B':
                        if (!TryParseHex(value, 4, out parsed))
                        {
                            error = string.Format(CultureInfo.InvariantCulture, "字段 B 格式错误: {0}", value);
                            return false;
                        }
                        s.RxBytes = parsed;
                        s.HasB = true;
                        break;

                    case 'U':
                        if (!TryParseDec(value, 1, out parsed))
                        {
                            error = string.Format(CultureInfo.InvariantCulture, "字段 U 格式错误: {0}", value);
                            return false;
                        }
                        s.BaudIndex = parsed;
                        s.HasU = true;
                        break;

                    case 'L':
                        if (!TryParseDec(value, 1, out parsed))
                        {
                            error = string.Format(CultureInfo.InvariantCulture, "字段 L 格式错误: {0}", value);
                            return false;
                        }
                        s.LinkOk = parsed;
                        s.HasL = true;
                        break;

                    default:
                        // 未知键：忽略，不报错。
                        break;
                }
            }

            if (!s.HasD)
            {
                error = "缺少 D 字段";
                return false;
            }

            sample = s;
            return true;
        }

        private static bool TryParseHex(string text, int maxDigits, out int value)
        {
            value = 0;
            if (text == null || text.Length == 0 || text.Length > maxDigits)
            {
                return false;
            }

            int v = 0;
            for (int i = 0; i < text.Length; i++)
            {
                char c = text[i];
                int d;
                if (c >= '0' && c <= '9')
                {
                    d = c - '0';
                }
                else if (c >= 'a' && c <= 'f')
                {
                    d = c - 'a' + 10;
                }
                else if (c >= 'A' && c <= 'F')
                {
                    d = c - 'A' + 10;
                }
                else
                {
                    return false;
                }
                v = (v << 4) | d;
            }

            value = v;
            return true;
        }

        private static bool TryParseDec(string text, int maxDigits, out int value)
        {
            value = 0;
            if (text == null || text.Length == 0 || text.Length > maxDigits)
            {
                return false;
            }

            int v = 0;
            for (int i = 0; i < text.Length; i++)
            {
                char c = text[i];
                if (c < '0' || c > '9')
                {
                    return false;
                }
                v = v * 10 + (c - '0');
            }

            value = v;
            return true;
        }
    }

    /// <summary>
    /// 串口字节流 -> 文本行 的装配器。
    /// 只接受可打印 ASCII（0x20..0x7E），按 '\n' 断行；
    /// 非可打印字节会丢弃当前半行并计入 DiscardedBytes（用于发现波特率不匹配）。
    /// </summary>
    public sealed class LineAssembler
    {
        public const int MaxLineLength = 256;

        private readonly StringBuilder _buffer = new StringBuilder(MaxLineLength);

        /// <summary>成功完整输出的行数。</summary>
        public long LinesCompleted { get; private set; }
        /// <summary>因非可打印字节而丢弃的半行数（不是字节数，按半行计）。</summary>
        public long DiscardedBytes { get; private set; }
        /// <summary>超长行被丢弃的次数。</summary>
        public long OverflowCount { get; private set; }

        /// <summary>
        /// 喂入一个字符；凑满一行时返回 true 并通过 line 输出（已去掉行尾 CR、首尾空白）。
        /// </summary>
        public bool Feed(char c, out string line)
        {
            line = null;

            if (c == '\n')
            {
                int len = _buffer.Length;
                while (len > 0 && _buffer[len - 1] == '\r')
                {
                    len--;
                }

                string text = _buffer.ToString(0, len).Trim();
                _buffer.Length = 0;

                if (text.Length == 0)
                {
                    return false;
                }

                LinesCompleted++;
                line = text;
                return true;
            }

            if (c == '\r')
            {
                // 行尾 CR 留给 '\n' 处理；孤立 CR 不产生行。
                return false;
            }

            if (c >= ' ' && c <= '~')
            {
                if (_buffer.Length < MaxLineLength)
                {
                    _buffer.Append(c);
                }
                else
                {
                    // 超长行：丢弃并重新开始，避免把后续数据粘在一条坏行上。
                    _buffer.Length = 0;
                    OverflowCount++;
                }
                return false;
            }

            // 非可打印字节（0x00、乱码等）：丢弃当前半行。
            if (_buffer.Length > 0 || true)
            {
                _buffer.Length = 0;
                DiscardedBytes++;
            }
            return false;
        }

        /// <summary>复位（连接/断开或切换端口时调用）。</summary>
        public void Reset()
        {
            _buffer.Length = 0;
        }
    }
}
