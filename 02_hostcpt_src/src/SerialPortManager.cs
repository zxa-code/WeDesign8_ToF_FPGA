using System;
using System.Diagnostics;
using System.IO;
using System.IO.Ports;
using System.Threading;

namespace SDAM_Rangefinder
{
    /// <summary>
    /// 纯接收串口管理器：打开端口 → 后台线程逐字节读 → 装配文本行 → 解析为 TofSample。
    /// 本版本**不发送任何字节**（FPGA 没有 PC→FPGA 接收通道，下发命令无人接收）。
    /// 所有事件都在后台接收线程上触发，界面层必须自己切回 UI 线程。
    /// </summary>
    public sealed class SerialPortManager : IDisposable
    {
        private readonly object _sync = new object();

        private SerialPort _port;
        private Thread _thread;
        private volatile bool _running;
        private volatile bool _connected;
        private long _bytesReceived;
        private long _linesReceived;
        private string _portName = string.Empty;
        private int _baudRate;

        /// <summary>成功解析出一行（后台线程触发）。</summary>
        public event Action<TofSample> SampleReceived;
        /// <summary>收到一行但解析失败：参数为 (原始行, 错误原因)。</summary>
        public event Action<string, string> ParseFailed;
        /// <summary>串口错误（打开失败、掉线等）。</summary>
        public event Action<string> ErrorOccurred;
        /// <summary>连接成功。</summary>
        public event Action Connected;
        /// <summary>连接已断开（主动断开或异常掉线，只触发一次）。</summary>
        public event Action Disconnected;

        public bool IsConnected { get { return _connected; } }
        public string PortName { get { return _portName; } }
        public int BaudRate { get { return _baudRate; } }
        public long BytesReceived { get { return Interlocked.Read(ref _bytesReceived); } }
        public long LinesReceived { get { return Interlocked.Read(ref _linesReceived); } }

        /// <summary>
        /// 打开串口并开始接收。8N1、DtrEnable、读超时 500 ms。
        /// </summary>
        public bool Connect(string portName, int baudRate)
        {
            string error = null;
            bool opened = false;

            lock (_sync)
            {
                if (_connected)
                {
                    error = "串口已连接，请先断开";
                }
                else if (string.IsNullOrEmpty(portName))
                {
                    error = "串口名为空";
                }
                else if (baudRate <= 0)
                {
                    error = "波特率无效";
                }
                else
                {
                    try
                    {
                        SerialPort port = new SerialPort(portName, baudRate, Parity.None, 8, StopBits.One);
                        port.Handshake = Handshake.None;
                        port.ReadTimeout = 500;
                        port.WriteTimeout = 500;
                        port.DtrEnable = true;
                        port.RtsEnable = false;
                        port.Open();
                        port.DiscardInBuffer();
                        port.DiscardOutBuffer();

                        _port = port;
                        _portName = portName;
                        _baudRate = baudRate;
                        Interlocked.Exchange(ref _bytesReceived, 0);
                        Interlocked.Exchange(ref _linesReceived, 0);
                        _running = true;
                        _connected = true;

                        _thread = new Thread(ReadLoop);
                        _thread.IsBackground = true;
                        _thread.Name = "SDAM 串口接收";
                        _thread.Start();

                        opened = true;
                    }
                    catch (Exception ex)
                    {
                        error = "打开串口失败: " + ex.Message;
                    }
                }
            }

            if (!opened)
            {
                RaiseError(error);
                return false;
            }

            Action handler = Connected;
            if (handler != null)
            {
                handler();
            }
            return true;
        }

        /// <summary>
        /// 主动断开：置停止标志 → 关端口解除阻塞 → 等待接收线程退出（最多 800 ms）。
        /// </summary>
        public void Disconnect()
        {
            Thread thread;
            lock (_sync)
            {
                if (!_connected && _port == null)
                {
                    return;
                }

                _running = false;
                thread = _thread;

                try
                {
                    if (_port != null && _port.IsOpen)
                    {
                        _port.Close();
                    }
                }
                catch
                {
                    // 关闭失败不影响后续清理。
                }
            }

            if (thread != null && thread != Thread.CurrentThread)
            {
                try
                {
                    thread.Join(800);
                }
                catch (ThreadStateException)
                {
                    // 线程尚未启动或已结束。
                }
            }
        }

        public void Dispose()
        {
            Disconnect();
            GC.SuppressFinalize(this);
        }

        private void ReadLoop()
        {
            LineAssembler assembler = new LineAssembler();

            try
            {
                while (_running)
                {
                    SerialPort port = _port;
                    if (port == null || !port.IsOpen)
                    {
                        break;
                    }

                    int value;
                    try
                    {
                        value = port.ReadByte();
                    }
                    catch (TimeoutException)
                    {
                        continue;
                    }
                    catch (InvalidOperationException)
                    {
                        break;
                    }
                    catch (IOException ex)
                    {
                        RaiseError("串口读取失败（可能被拔出）: " + ex.Message);
                        break;
                    }

                    if (value < 0)
                    {
                        continue;
                    }

                    Interlocked.Increment(ref _bytesReceived);

                    string line;
                    if (!assembler.Feed((char)value, out line))
                    {
                        continue;
                    }

                    Interlocked.Increment(ref _linesReceived);

                    TofSample sample;
                    string parseError;
                    if (TofLineParser.TryParse(line, DateTime.Now, Stopwatch.GetTimestamp(), out sample, out parseError))
                    {
                        Action<TofSample> handler = SampleReceived;
                        if (handler != null)
                        {
                            handler(sample);
                        }
                    }
                    else
                    {
                        Action<string, string> handler = ParseFailed;
                        if (handler != null)
                        {
                            handler(line, parseError);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                RaiseError("串口接收线程异常: " + ex.Message);
            }
            finally
            {
                bool wasConnected = _connected;
                _connected = false;
                _running = false;

                try
                {
                    if (_port != null && _port.IsOpen)
                    {
                        _port.Close();
                    }
                }
                catch
                {
                    // 忽略关闭异常。
                }

                _thread = null;

                if (wasConnected)
                {
                    Action handler = Disconnected;
                    if (handler != null)
                    {
                        handler();
                    }
                }
            }
        }

        private void RaiseError(string message)
        {
            Action<string> handler = ErrorOccurred;
            if (handler != null)
            {
                handler(message);
            }
        }
    }
}
