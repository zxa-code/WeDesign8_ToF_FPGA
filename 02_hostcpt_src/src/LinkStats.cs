using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace SDAM_Rangefinder
{
    /// <summary>
    /// 由 FPGA 上行行内的计数（F/C/B）推算链路质量。
    /// 下位机每个样本只给 16 位/8 位计数器，因此必须做回绕处理：
    ///   ΔF = (F2 - F1) &amp; 0xFFFF，ΔC = (C2 - C1) &amp; 0xFF，ΔB = (B2 - B1) &amp; 0xFFFF。
    /// 只保留最近 1.5 s 的样本，在 1.0 s 窗口上求平均；窗口不足 0.5 s 时结果标为无效，
    /// 避免刚连接时出现跳变数字。
    /// </summary>
    public sealed class LinkStats
    {
        /// <summary>F 计数在 1 s 内正常增长约 100，超过此值视为下位机复位/换源，不是回绕。</summary>
        private const int ResetDeltaThreshold = 1000;

        private struct Point
        {
            public long Ts;
            public int F;
            public int C;
            public int B;
            public bool HasF;
            public bool HasC;
            public bool HasB;
        }

        private readonly List<Point> _points = new List<Point>(64);
        private readonly double _freq = Stopwatch.Frequency;
        private readonly long _keepTicks;
        private readonly long _windowTicks;

        private bool _hasLastF;
        private int _lastF;
        private bool _boardResetPending;

        /// <summary>ToF 模块出帧率（fps），由 F 计数推算。无效时为 0。</summary>
        public double TofFps { get; private set; }
        /// <summary>每秒 CRC 错误数（C 计数只有低 8 位）。</summary>
        public double CrcErrPerSec { get; private set; }
        /// <summary>每秒 FPGA 收到的模块字节数（B 计数只有低 16 位）。</summary>
        public double BytesPerSec { get; private set; }
        /// <summary>每秒收到的完整文本行数。</summary>
        public double LineRateHz { get; private set; }
        /// <summary>窗口内 B 与 23×F 不一致（且无 CRC 错）——可能丢字节/多字节。</summary>
        public bool ByteFrameMismatch { get; private set; }
        /// <summary>至少积累 0.5 s 数据，统计值可信。</summary>
        public bool Valid { get; private set; }

        public LinkStats()
        {
            _keepTicks = (long)(_freq * 1.5);
            _windowTicks = (long)(_freq * 1.0);
        }

        /// <summary>下位机复位事件（只报一次）：由 UI 决定是否写日志。</summary>
        public bool ConsumeBoardReset()
        {
            bool v = _boardResetPending;
            _boardResetPending = false;
            return v;
        }

        /// <summary>波特率档位 → 实际波特率；未知档返回 -1。</summary>
        public static int BaudRateFromIndex(int index)
        {
            switch (index)
            {
                case 0: return 9600;
                case 1: return 115200;
                case 2: return 230400;
                case 3: return 921600;
                default: return -1;
            }
        }

        /// <summary>喂入一个样本（每行一次）。</summary>
        public void Update(TofSample sample)
        {
            if (sample == null)
            {
                return;
            }

            long now = sample.Timestamp;

            // 1) 复位检测：正常时 F 每行只加几到几十；骤降且不满足回绕特征 = 下位机重启。
            if (sample.HasF && _hasLastF)
            {
                bool reset = false;
                if (sample.FrameCount < _lastF)
                {
                    bool looksLikeWrap = _lastF >= 65000 && sample.FrameCount <= 500;
                    reset = !looksLikeWrap;
                }
                else if (sample.FrameCount - _lastF > ResetDeltaThreshold)
                {
                    reset = true;
                }

                if (reset)
                {
                    _points.Clear();
                    _boardResetPending = true;
                    TofFps = 0;
                    CrcErrPerSec = 0;
                    BytesPerSec = 0;
                    LineRateHz = 0;
                    ByteFrameMismatch = false;
                    Valid = false;
                }
            }

            if (sample.HasF)
            {
                _lastF = sample.FrameCount;
                _hasLastF = true;
            }

            // 2) 入窗并修剪过期点。
            Point p = new Point();
            p.Ts = now;
            p.F = sample.FrameCount;
            p.C = sample.CrcErrors;
            p.B = sample.RxBytes;
            p.HasF = sample.HasF;
            p.HasC = sample.HasC;
            p.HasB = sample.HasB;
            _points.Add(p);

            long keepFrom = now - _keepTicks;
            int drop = 0;
            while (drop < _points.Count && _points[drop].Ts < keepFrom)
            {
                drop++;
            }
            if (drop > 0)
            {
                _points.RemoveRange(0, drop);
            }

            // 3) 取 1.0 s 窗口内的首尾点。
            long windowFrom = now - _windowTicks;
            int start = 0;
            while (start < _points.Count && _points[start].Ts < windowFrom)
            {
                start++;
            }

            int lastIndex = _points.Count - 1;
            if (start >= lastIndex)
            {
                Valid = false;
                return;
            }

            Point last = _points[lastIndex];
            Point first = _points[start];
            double dtAll = (double)(last.Ts - first.Ts) / _freq;
            if (dtAll < 0.5)
            {
                Valid = false;
                return;
            }

            // 行率：窗口内行数 / 时间。
            LineRateHz = (double)(lastIndex - start) / dtAll;

            // 4) F/C/B 增量（用窗口内各自首尾有效点，避免缺字段时算出 0）。
            int iFirstF = -1;
            int iLastF = -1;
            int iFirstC = -1;
            int iLastC = -1;
            int iFirstB = -1;
            int iLastB = -1;
            for (int i = start; i <= lastIndex; i++)
            {
                Point q = _points[i];
                if (q.HasF)
                {
                    if (iFirstF < 0) iFirstF = i;
                    iLastF = i;
                }
                if (q.HasC)
                {
                    if (iFirstC < 0) iFirstC = i;
                    iLastC = i;
                }
                if (q.HasB)
                {
                    if (iFirstB < 0) iFirstB = i;
                    iLastB = i;
                }
            }

            if (iFirstF >= 0 && iLastF > iFirstF)
            {
                Point a = _points[iFirstF];
                Point b = _points[iLastF];
                double dt = (double)(b.Ts - a.Ts) / _freq;
                if (dt >= 0.5)
                {
                    int dF = (b.F - a.F) & 0xFFFF;
                    TofFps = (double)dF / dt;
                }
            }

            if (iFirstC >= 0 && iLastC > iFirstC)
            {
                Point a = _points[iFirstC];
                Point b = _points[iLastC];
                double dt = (double)(b.Ts - a.Ts) / _freq;
                if (dt >= 0.5)
                {
                    int dC = (b.C - a.C) & 0xFF;
                    CrcErrPerSec = (double)dC / dt;
                }
            }

            if (iFirstB >= 0 && iLastB > iFirstB)
            {
                Point a = _points[iFirstB];
                Point b = _points[iLastB];
                double dt = (double)(b.Ts - a.Ts) / _freq;
                if (dt >= 0.5)
                {
                    int dB = (b.B - a.B) & 0xFFFF;
                    BytesPerSec = (double)dB / dt;
                }
            }

            // 5) 字节/帧一致性：无 CRC 错时，B 应严格按 23 B/帧增长。
            if (iFirstF >= 0 && iLastF > iFirstF && iFirstB >= 0 && iLastB > iFirstB
                && _points[iFirstF].HasC && _points[iLastF].HasC)
            {
                Point f0 = _points[iFirstF];
                Point f1 = _points[iLastF];
                Point b0 = _points[iFirstB];
                Point b1 = _points[iLastB];
                int dF = (f1.F - f0.F) & 0xFFFF;
                int dB = (b1.B - b0.B) & 0xFFFF;
                int dC = (f1.C - f0.C) & 0xFF;
                if (dF > 0)
                {
                    ByteFrameMismatch = dC == 0 && Math.Abs(dB - 23 * dF) > 46;
                }
            }

            Valid = true;
        }

        /// <summary>清空统计（断开/清屏/下位机复位后调用）。</summary>
        public void Reset()
        {
            _points.Clear();
            _hasLastF = false;
            _lastF = 0;
            _boardResetPending = false;
            TofFps = 0;
            CrcErrPerSec = 0;
            BytesPerSec = 0;
            LineRateHz = 0;
            ByteFrameMismatch = false;
            Valid = false;
        }
    }

    /// <summary>
    /// 会话统计：只统计有效距离样本；标准差用 Welford 在线算法（总体 σ，除以 N）。
    /// </summary>
    public sealed class SessionStats
    {
        private long _count;
        private double _mean;
        private double _m2;
        private int _min;
        private int _max;

        public long Count { get { return _count; } }
        public double Mean { get { return _count > 0 ? _mean : 0.0; } }
        public double StdDev { get { return _count > 0 ? Math.Sqrt(_m2 / _count) : 0.0; } }
        public int Min { get { return _count > 0 ? _min : 0; } }
        public int Max { get { return _count > 0 ? _max : 0; } }

        public void Add(int value)
        {
            _count++;
            double delta = value - _mean;
            _mean += delta / _count;
            _m2 += delta * (value - _mean);

            if (_count == 1)
            {
                _min = value;
                _max = value;
            }
            else
            {
                if (value < _min) _min = value;
                if (value > _max) _max = value;
            }
        }

        public void Reset()
        {
            _count = 0;
            _mean = 0;
            _m2 = 0;
            _min = 0;
            _max = 0;
        }
    }
}
