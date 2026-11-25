using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Ports;
using System.Text;
using System.Windows.Forms;
using System.Windows.Forms.DataVisualization.Charting;

namespace SDAM_Rangefinder
{
    /// <summary>
    /// 主界面：纯接收 FPGA 上行文本行，显示实时值、三曲线、链路诊断、会话统计与日志。
    /// 纯接收设计：不向串口写入任何字节，不提供开始测量/停止测量/设备设置。
    /// </summary>
    public partial class MainForm : Form
    {
        private const int MaxSampleQueue = 500;
        private const int MaxLogQueue = 800;
        private const int MaxHistory = 100000;
        private const int UiIntervalMs = 100;
        private const int LogTrimChars = 120000;

        private readonly object _queueLock = new object();
        private readonly Queue<TofSample> _sampleQueue = new Queue<TofSample>();
        private readonly Queue<string> _logQueue = new Queue<string>();
        private readonly Queue<TofSample> _history = new Queue<TofSample>();
        private readonly LinkStats _linkStats = new LinkStats();
        private readonly SessionStats _sessionStats = new SessionStats();
        private readonly SerialPortManager _serial = new SerialPortManager();
        private readonly Timer _uiTimer = new Timer();

        private Series _seriesDistance;
        private Series _seriesIntensity;
        private Series _seriesAmbient;

        private bool _connected;
        private bool _disconnectLogged;
        private bool _userDisconnecting;
        private DateTime _connectedAt = DateTime.MinValue;
        private DateTime _lastSampleAt = DateTime.MinValue;
        private TofSample _lastSample;
        private long _droppedSamples;
        private long _droppedReported;
        private int _windowSeconds = 30;
        private int _parseErrorCount;
        private bool _warnedNoLine;
        private bool _warnedBaud;
        private bool _warnedStall;

        public MainForm()
        {
            InitializeComponent();
            InitializeChart();

            _serial.SampleReceived += OnSampleReceived;
            _serial.ParseFailed += OnParseFailed;
            _serial.ErrorOccurred += OnSerialError;
            _serial.Disconnected += OnSerialDisconnected;

            _uiTimer.Interval = UiIntervalMs;
            _uiTimer.Tick += UiTimer_Tick;
            _uiTimer.Start();

            RefreshPorts();
            SetConnectedState(false);
            UpdateStatsLabel();
            UpdateDiagnostics();
        }

        // ------------------------------------------------------------------
        // 初始化
        // ------------------------------------------------------------------

        private void InitializeChart()
        {
            chartDistance.ChartAreas.Clear();
            chartDistance.Series.Clear();
            chartDistance.Legends.Clear();
            chartDistance.BackColor = Color.White;

            ChartArea area = new ChartArea("main");
            area.BackColor = Color.White;
            area.AxisX.LabelStyle.Format = "HH:mm:ss";
            area.AxisX.LabelStyle.Font = new Font("微软雅黑", 8F);
            area.AxisX.MajorGrid.LineColor = Color.Gainsboro;
            area.AxisX.IntervalType = DateTimeIntervalType.Seconds;
            area.AxisX.Interval = 5;
            area.AxisX.Minimum = DateTime.Now.AddSeconds(-_windowSeconds).ToOADate();
            area.AxisX.Maximum = DateTime.Now.ToOADate();
            area.AxisY.Title = "距离 (mm)";
            area.AxisY.LabelStyle.Font = new Font("微软雅黑", 8F);
            area.AxisY.MajorGrid.LineColor = Color.Gainsboro;
            area.AxisY2.Enabled = AxisEnabled.True;
            area.AxisY2.Title = "强度 / 环境光（原始值）";
            area.AxisY2.LabelStyle.Font = new Font("微软雅黑", 8F);
            chartDistance.ChartAreas.Add(area);

            Legend legend = new Legend("mainLegend");
            legend.Docking = Docking.Top;
            legend.Font = new Font("微软雅黑", 8F);
            chartDistance.Legends.Add(legend);

            _seriesDistance = CreateSeries("距离 (mm)", Color.RoyalBlue, AxisType.Primary);
            _seriesIntensity = CreateSeries("强度", Color.SeaGreen, AxisType.Secondary);
            _seriesAmbient = CreateSeries("环境光", Color.DarkOrange, AxisType.Secondary);

            chartDistance.Series.Add(_seriesDistance);
            chartDistance.Series.Add(_seriesIntensity);
            chartDistance.Series.Add(_seriesAmbient);

            // 按复选框初始状态显示。
            ApplySeriesVisibility();
        }

        private static Series CreateSeries(string name, Color color, AxisType axisType)
        {
            Series series = new Series(name);
            series.ChartType = SeriesChartType.Line;
            series.XValueType = ChartValueType.DateTime;
            series.YAxisType = axisType;
            series.BorderWidth = 2;
            series.Color = color;
            series.ChartArea = "main";
            return series;
        }

        // ------------------------------------------------------------------
        // 串口事件（后台线程）
        // ------------------------------------------------------------------

        private void OnSampleReceived(TofSample sample)
        {
            if (sample == null)
            {
                return;
            }

            lock (_queueLock)
            {
                if (_sampleQueue.Count >= MaxSampleQueue)
                {
                    _sampleQueue.Dequeue();
                    System.Threading.Interlocked.Increment(ref _droppedSamples);
                }
                _sampleQueue.Enqueue(sample);
            }
        }

        private void OnParseFailed(string line, string error)
        {
            int count = System.Threading.Interlocked.Increment(ref _parseErrorCount);
            if (count <= 20 || count % 50 == 0)
            {
                EnqueueLog(string.Format(CultureInfo.InvariantCulture,
                    "解析失败（第 {0} 次）: {1} | 行: {2}", count, error, Truncate(line, 80)));
            }
            if (count == 5)
            {
                EnqueueLog("连续收到无法解析的数据：请检查波特率是否与拨码 U 档一致、TX/RX 接线与共地。");
            }
        }

        private void OnSerialError(string message)
        {
            EnqueueLog("串口错误: " + message);
        }

        private void OnSerialDisconnected()
        {
            try
            {
                if (IsHandleCreated && !IsDisposed)
                {
                    BeginInvoke(new Action(HandleDisconnected));
                    return;
                }
            }
            catch (InvalidOperationException)
            {
                // 窗口正在关闭，直接走下面的同步处理。
            }
            HandleDisconnected();
        }

        private void HandleDisconnected()
        {
            if (_disconnectLogged)
            {
                return;
            }
            _disconnectLogged = true;
            _connected = false;
            SetConnectedState(false);
            if (!_userDisconnecting)
            {
                EnqueueLog("串口连接已断开（设备掉线或端口被占用）。");
            }
        }

        // ------------------------------------------------------------------
        // UI 定时刷新
        // ------------------------------------------------------------------

        private void UiTimer_Tick(object sender, EventArgs e)
        {
            DrainLog();
            DrainSamples();
            UpdateDiagnostics();
            if (_connected)
            {
                UpdateChartAxes();
                CheckLinkWarnings();
            }
        }

        private void DrainLog()
        {
            StringBuilder sb = new StringBuilder();
            lock (_queueLock)
            {
                while (_logQueue.Count > 0)
                {
                    sb.Append(_logQueue.Dequeue());
                    sb.Append("\r\n");
                }
            }

            if (sb.Length == 0)
            {
                return;
            }

            if (txtLog.TextLength > LogTrimChars)
            {
                txtLog.Clear();
                txtLog.AppendText("[日志过长，已自动清空]\r\n");
            }
            txtLog.AppendText(sb.ToString());
            txtLog.SelectionStart = txtLog.TextLength;
            txtLog.ScrollToCaret();
        }

        private void DrainSamples()
        {
            List<TofSample> batch = new List<TofSample>();
            lock (_queueLock)
            {
                while (_sampleQueue.Count > 0)
                {
                    batch.Add(_sampleQueue.Dequeue());
                }
            }

            if (batch.Count == 0)
            {
                return;
            }

            bool statsDirty = false;

            for (int i = 0; i < batch.Count; i++)
            {
                TofSample s = batch[i];
                _lastSample = s;
                _lastSampleAt = s.ReceivedAt;

                _history.Enqueue(s);
                while (_history.Count > MaxHistory)
                {
                    _history.Dequeue();
                }

                if (s.DistanceValid)
                {
                    _sessionStats.Add(s.Distance);
                    statsDirty = true;
                }

                _linkStats.Update(s);
                if (_linkStats.ConsumeBoardReset())
                {
                    EnqueueLog("下位机计数复位（可能重新上电/下载），统计窗已重置。");
                }

                AddChartPoints(s);
                UpdateLiveLabels(s);
                CheckBaudMismatch(s);
            }

            if (statsDirty)
            {
                UpdateStatsLabel();
            }

            long dropped = System.Threading.Interlocked.Read(ref _droppedSamples);
            if (dropped > _droppedReported + 50)
            {
                EnqueueLog(string.Format(CultureInfo.InvariantCulture,
                    "界面接收队列溢出，已丢弃约 {0} 条样本（界面刷新跟不上）。", dropped));
                _droppedReported = dropped;
            }
        }

        private void AddChartPoints(TofSample s)
        {
            double x = s.ReceivedAt.ToOADate();
            if (s.DistanceValid)
            {
                _seriesDistance.Points.AddXY(x, s.Distance);
            }
            if (s.HasI)
            {
                _seriesIntensity.Points.AddXY(x, s.Intensity);
            }
            if (s.HasA)
            {
                _seriesAmbient.Points.AddXY(x, s.Ambient);
            }
        }

        private void UpdateLiveLabels(TofSample s)
        {
            if (s.DistanceValid)
            {
                lblDistanceValue.Text = s.Distance.ToString(CultureInfo.InvariantCulture) + " mm";
            }
            else if (s.HasD && (s.Distance == 0 || s.Distance == 0xFFFF))
            {
                lblDistanceValue.Text = "无目标";
            }
            else
            {
                lblDistanceValue.Text = "---";
            }

            lblIntensityValue.Text = s.HasI ? s.Intensity.ToString(CultureInfo.InvariantCulture) : "---";
            lblAmbientValue.Text = s.HasA ? s.Ambient.ToString(CultureInfo.InvariantCulture) : "---";
        }

        private void UpdateChartAxes()
        {
            if (chartDistance.ChartAreas.Count == 0)
            {
                return;
            }

            ChartArea area = chartDistance.ChartAreas[0];
            DateTime now = DateTime.Now;
            double min = now.AddSeconds(-_windowSeconds).ToOADate();
            double max = now.ToOADate();

            TrimSeries(_seriesDistance, min);
            TrimSeries(_seriesIntensity, min);
            TrimSeries(_seriesAmbient, min);

            area.AxisX.Minimum = min;
            area.AxisX.Maximum = max;
            area.AxisX.Interval = Math.Max(1, _windowSeconds / 6);
            area.AxisX.IntervalType = DateTimeIntervalType.Seconds;
        }

        private static void TrimSeries(Series series, double min)
        {
            if (series == null)
            {
                return;
            }
            while (series.Points.Count > 0 && series.Points[0].XValue < min)
            {
                series.Points.RemoveAt(0);
            }
        }

        private void UpdateDiagnostics()
        {
            TofSample s = _lastSample;

            string link = "—";
            string frames = "—";
            string bytes = "—";
            string uText = "—";
            if (s != null)
            {
                if (s.HasL)
                {
                    link = s.LinkOk == 1 ? "正常" : "断";
                }
                if (s.HasF)
                {
                    frames = s.FrameCount.ToString(CultureInfo.InvariantCulture);
                }
                if (s.HasB)
                {
                    bytes = s.RxBytes.ToString(CultureInfo.InvariantCulture);
                }
                if (s.HasU)
                {
                    int rate = LinkStats.BaudRateFromIndex(s.BaudIndex);
                    string mismatch = (_connected && rate > 0 && rate != _serial.BaudRate) ? "（与所选不符）" : "";
                    uText = string.Format(CultureInfo.InvariantCulture, "{0} → {1}{2}",
                        s.BaudIndex, rate > 0 ? rate.ToString(CultureInfo.InvariantCulture) : "?", mismatch);
                }
            }

            string crcRate = _linkStats.Valid ? _linkStats.CrcErrPerSec.ToString("F1", CultureInfo.InvariantCulture) : "—";
            string lineRate = _linkStats.Valid ? _linkStats.LineRateHz.ToString("F1", CultureInfo.InvariantCulture) : "—";
            string fps = _linkStats.Valid ? _linkStats.TofFps.ToString("F1", CultureInfo.InvariantCulture) : "—";
            string byteFrame = _linkStats.Valid ? (_linkStats.ByteFrameMismatch ? "不一致" : "一致") : "—";

            lblDiag.Text = string.Format(CultureInfo.InvariantCulture,
                "链路: {0}    CRC: {1}/s\r\n帧计数: {2}    收字节: {3}\r\n行率: {4} 行/s    模块帧率: {5} fps\r\nU 档位: {6}    字节/帧: {7}\r\n模块链路: 921600 8N1（FPGA 固定）",
                link, crcRate, frames, bytes, lineRate, fps, uText, byteFrame);
        }

        private void UpdateStatsLabel()
        {
            if (_sessionStats.Count == 0)
            {
                lblStats.Text = "样本数 N: 0\r\n均值: —\r\n标准差 σ: —\r\n最小值: —\r\n最大值: —\r\n峰值差: —\r\n\r\n说明：\r\nσ 为总体标准差（除以 N）；\r\n只统计有效距离样本。";
                return;
            }

            lblStats.Text = string.Format(CultureInfo.InvariantCulture,
                "样本数 N: {0}\r\n均值: {1:F2} mm\r\n标准差 σ: {2:F2} mm\r\n最小值: {3} mm\r\n最大值: {4} mm\r\n峰值差: {5} mm\r\n\r\n说明：\r\nσ 为总体标准差（除以 N）；\r\n只统计有效距离样本。",
                _sessionStats.Count, _sessionStats.Mean, _sessionStats.StdDev,
                _sessionStats.Min, _sessionStats.Max, _sessionStats.Max - _sessionStats.Min);
        }

        private void CheckBaudMismatch(TofSample s)
        {
            if (_warnedBaud || !s.HasU || !_connected)
            {
                return;
            }

            int rate = LinkStats.BaudRateFromIndex(s.BaudIndex);
            if (rate <= 0)
            {
                EnqueueLog(string.Format(CultureInfo.InvariantCulture,
                    "收到未知 U 档位 {0}：下位机固件可能已升级，请检查拨码与协议文档。", s.BaudIndex));
                _warnedBaud = true;
                return;
            }

            if (rate != _serial.BaudRate)
            {
                EnqueueLog(string.Format(CultureInfo.InvariantCulture,
                    "波特率不匹配：下位机 U={0}（{1}），上位机当前 {2}。请选择 {1} 后重新连接。",
                    s.BaudIndex, rate, _serial.BaudRate));
                _warnedBaud = true;
            }
        }

        private void CheckLinkWarnings()
        {
            DateTime now = DateTime.Now;

            if (_lastSampleAt == DateTime.MinValue)
            {
                if (!_warnedNoLine && now - _connectedAt > TimeSpan.FromSeconds(2))
                {
                    EnqueueLog("连接后 2 秒未收到完整数据行：请确认拨码 U 档与所选波特率一致（0 个或多个拨码 ON 时 FPGA 不发送）。");
                    _warnedNoLine = true;
                }
                return;
            }

            if (!_warnedStall && now - _lastSampleAt > TimeSpan.FromSeconds(2))
            {
                EnqueueLog("已超过 2 秒未收到数据行：检查 USB 线/接口，或下位机是否掉电。");
                _warnedStall = true;
            }
        }

        // ------------------------------------------------------------------
        // 按钮与界面事件
        // ------------------------------------------------------------------

        private void btnRefreshPorts_Click(object sender, EventArgs e)
        {
            RefreshPorts();
            EnqueueLog(string.Format(CultureInfo.InvariantCulture, "串口列表已刷新，共 {0} 个端口。", comboBoxPort.Items.Count));
        }

        private void btnConnect_Click(object sender, EventArgs e)
        {
            if (_connected)
            {
                DisconnectCurrent(true);
                return;
            }

            string port = comboBoxPort.Text.Trim();
            if (port.Length == 0)
            {
                EnqueueLog("请先选择串口（可点“刷新端口”）。");
                return;
            }

            int baud;
            if (!int.TryParse(comboBoxBaudRate.Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out baud))
            {
                EnqueueLog("波特率无效。");
                return;
            }

            btnConnect.Enabled = false;
            bool ok;
            try
            {
                ok = _serial.Connect(port, baud);
            }
            finally
            {
                btnConnect.Enabled = true;
            }

            if (!ok)
            {
                // 具体原因已由 ErrorOccurred 写入日志。
                EnqueueLog("连接失败。");
                return;
            }

            _connected = true;
            _disconnectLogged = false;
            _connectedAt = DateTime.Now;
            _lastSampleAt = DateTime.MinValue;
            _lastSample = null;
            System.Threading.Interlocked.Exchange(ref _parseErrorCount, 0);
            _warnedNoLine = false;
            _warnedBaud = false;
            _warnedStall = false;
            System.Threading.Interlocked.Exchange(ref _droppedSamples, 0);
            _droppedReported = 0;
            _linkStats.Reset();

            ClearData();

            SetConnectedState(true);
            _uiTimer.Start();
            EnqueueLog(string.Format(CultureInfo.InvariantCulture,
                "已连接 {0} @ {1} 8N1，等待数据行…", port, baud));
        }

        private void DisconnectCurrent(bool userInitiated)
        {
            _userDisconnecting = userInitiated;
            try
            {
                _serial.Disconnect();
            }
            finally
            {
                _userDisconnecting = false;
            }

            _connected = false;
            _disconnectLogged = true;
            SetConnectedState(false);
            ResetLiveLabels();
            if (userInitiated)
            {
                EnqueueLog("已断开串口。");
            }
            DrainLog();
        }

        private void btnClearChart_Click(object sender, EventArgs e)
        {
            ClearData();
            EnqueueLog("曲线、会话统计与历史缓存已清空（此后保存的 CSV 只含清空后的数据）。");
        }

        private void ClearData()
        {
            _seriesDistance.Points.Clear();
            _seriesIntensity.Points.Clear();
            _seriesAmbient.Points.Clear();
            _history.Clear();
            _sessionStats.Reset();
            UpdateStatsLabel();
        }

        private void btnSaveCsv_Click(object sender, EventArgs e)
        {
            if (_history.Count == 0)
            {
                MessageBox.Show("当前没有可保存的数据。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            using (SaveFileDialog dialog = new SaveFileDialog())
            {
                dialog.Filter = "CSV 文件|*.csv|所有文件|*.*";
                dialog.FileName = "SDAM_data_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".csv";
                if (dialog.ShowDialog(this) != DialogResult.OK)
                {
                    return;
                }

                try
                {
                    SaveCsv(dialog.FileName);
                    EnqueueLog("已保存 CSV: " + dialog.FileName);
                }
                catch (Exception ex)
                {
                    EnqueueLog("保存 CSV 失败: " + ex.Message);
                    MessageBox.Show("保存 CSV 失败：\r\n" + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void SaveCsv(string path)
        {
            using (StreamWriter writer = new StreamWriter(path, false, new UTF8Encoding(true)))
            {
                writer.WriteLine("序号,时间,距离_mm,强度,环境光,CRC错,帧计数,波特率档,收字节,链路,原始行");
                int index = 0;
                foreach (TofSample s in _history)
                {
                    index++;
                    writer.WriteLine(string.Format(CultureInfo.InvariantCulture,
                        "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}",
                        index,
                        s.ReceivedAt.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture),
                        Field(s.Distance), Field(s.Intensity), Field(s.Ambient),
                        Field(s.CrcErrors), Field(s.FrameCount), Field(s.BaudIndex),
                        Field(s.RxBytes), Field(s.LinkOk), Sanitize(s.RawLine)));
                }
            }
        }

        private static string Field(int value)
        {
            return value == TofSample.Missing ? string.Empty : value.ToString(CultureInfo.InvariantCulture);
        }

        private static string Sanitize(string text)
        {
            if (text == null)
            {
                return string.Empty;
            }
            return text.Replace(",", ";").Replace("\"", "'");
        }

        private void btnSavePng_Click(object sender, EventArgs e)
        {
            using (SaveFileDialog dialog = new SaveFileDialog())
            {
                dialog.Filter = "PNG 图片|*.png|所有文件|*.*";
                dialog.FileName = "SDAM_curve_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".png";
                if (dialog.ShowDialog(this) != DialogResult.OK)
                {
                    return;
                }

                try
                {
                    chartDistance.SaveImage(dialog.FileName, ChartImageFormat.Png);
                    EnqueueLog("已保存曲线截图: " + dialog.FileName);
                }
                catch (Exception ex)
                {
                    EnqueueLog("保存 PNG 失败: " + ex.Message);
                    MessageBox.Show("保存 PNG 失败：\r\n" + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void btnClearLog_Click(object sender, EventArgs e)
        {
            txtLog.Clear();
        }

        private void chkSeries_CheckedChanged(object sender, EventArgs e)
        {
            ApplySeriesVisibility();
        }

        private void ApplySeriesVisibility()
        {
            if (_seriesDistance == null)
            {
                return;
            }
            _seriesDistance.Enabled = chkDistance.Checked;
            _seriesIntensity.Enabled = chkIntensity.Checked;
            _seriesAmbient.Enabled = chkAmbient.Checked;
        }

        private void comboBoxWindow_SelectedIndexChanged(object sender, EventArgs e)
        {
            switch (comboBoxWindow.SelectedIndex)
            {
                case 0: _windowSeconds = 10; break;
                case 1: _windowSeconds = 30; break;
                case 2: _windowSeconds = 60; break;
                case 3: _windowSeconds = 300; break;
                default: _windowSeconds = 30; break;
            }
            UpdateChartAxes();
        }

        private void MainForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            _uiTimer.Stop();
            try
            {
                _serial.Disconnect();
            }
            catch
            {
                // 关闭阶段忽略异常。
            }
        }

        // ------------------------------------------------------------------
        // 辅助
        // ------------------------------------------------------------------

        private void RefreshPorts()
        {
            string current = comboBoxPort.Text;
            comboBoxPort.Items.Clear();

            string[] names = SerialPort.GetPortNames();
            Array.Sort(names, StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < names.Length; i++)
            {
                comboBoxPort.Items.Add(names[i]);
            }

            if (names.Length == 0)
            {
                return;
            }

            int index = Array.IndexOf(names, current);
            comboBoxPort.SelectedIndex = index >= 0 ? index : 0;
        }

        private void SetConnectedState(bool connected)
        {
            comboBoxPort.Enabled = !connected;
            comboBoxBaudRate.Enabled = !connected;
            btnRefreshPorts.Enabled = !connected;
            btnConnect.Text = connected ? "断开" : "连接";

            if (connected)
            {
                lblConnState.Text = string.Format(CultureInfo.InvariantCulture,
                    "已连接 {0} @ {1}", _serial.PortName, _serial.BaudRate);
                lblConnState.ForeColor = Color.Green;
            }
            else
            {
                lblConnState.Text = "未连接";
                lblConnState.ForeColor = Color.DimGray;
            }
        }

        private void ResetLiveLabels()
        {
            lblDistanceValue.Text = "---";
            lblIntensityValue.Text = "---";
            lblAmbientValue.Text = "---";
        }

        private void EnqueueLog(string message)
        {
            if (message == null)
            {
                return;
            }

            string line = DateTime.Now.ToString("HH:mm:ss.fff", CultureInfo.InvariantCulture) + "  " + message;
            lock (_queueLock)
            {
                if (_logQueue.Count >= MaxLogQueue)
                {
                    _logQueue.Dequeue();
                }
                _logQueue.Enqueue(line);
            }
        }

        private static string Truncate(string text, int maxLength)
        {
            if (text == null)
            {
                return string.Empty;
            }
            if (text.Length <= maxLength)
            {
                return text;
            }
            return text.Substring(0, maxLength) + "…";
        }
    }
}
